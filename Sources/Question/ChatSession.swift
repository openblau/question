import Foundation
import Observation

/// One incognito conversation. Lives only in memory; `end()` wipes it.
@MainActor
@Observable
final class ChatSession {
    struct Source: Hashable { let title: String; let url: String }

    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var status: String? = "Thinking…"
        var sources: [Source] = []
        var error: String?
        var done = false
    }

    private(set) var turns: [Turn] = []
    private(set) var isBusy = false
    private(set) var apiKey: String?
    private(set) var backend: Backend
    var focusTick = 0

    /// Where answers come from: the user's Claude subscription (via Claude Code) or an API key.
    enum Backend: String {
        case subscription, apiKey
        var label: String { self == .subscription ? "Claude subscription" : "API key" }
    }

    private static let backendKey = "backend"

    @ObservationIgnored private var history: [[String: Any]] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var system = ChatSession.makeSystemPrompt()
    @ObservationIgnored private var claudeCode: ClaudeCodeClient?
    @ObservationIgnored private var generation = 0

    init() {
        let environmentKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        // First launch: keep using a key that's already set up, otherwise prefer the subscription.
        let hasKey = environmentKey != nil || Keychain.exists
        let backend = UserDefaults.standard.string(forKey: Self.backendKey).flatMap(Backend.init)
            ?? (!hasKey && ClaudeCodeClient.executable != nil ? .subscription : .apiKey)
        self.backend = backend
        // Only touch the key itself when it will be used, so subscription users never see a Keychain prompt.
        apiKey = backend == .apiKey ? environmentKey ?? Keychain.read() : nil
    }

    var needsKey: Bool { backend == .apiKey && apiKey == nil }

    /// Switching ends the session: the two backends don't share a conversation.
    func use(_ backend: Backend) {
        guard backend != self.backend else { return }
        end()
        self.backend = backend
        if backend == .apiKey, apiKey == nil {
            apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
                ?? Keychain.read()
        }
        UserDefaults.standard.set(backend.rawValue, forKey: Self.backendKey)
    }

    /// Saves to the Keychain first; the key is only used if that succeeds.
    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try Keychain.save(trimmed)
        apiKey = trimmed
        use(.apiKey)
    }

    func forgetKey() {
        Keychain.delete()
        apiKey = nil
        end()
    }

    /// Ends the session: cancels any request and drops every message from memory.
    func end() {
        generation += 1
        task?.cancel()
        task = nil
        claudeCode?.terminate()
        claudeCode = nil
        turns = []
        history = []
        isBusy = false
        system = Self.makeSystemPrompt()
    }

    func stop() { task?.cancel() }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy, !needsKey else { return }

        turns.append(Turn(question: question))
        let turnIndex = turns.count - 1
        let generation = generation
        isBusy = true

        task = Task { [weak self] in
            guard let self else { return }
            var failure: String?
            do {
                let stop = switch backend {
                case .subscription: try await askClaudeCode(question, turnIndex: turnIndex)
                case .apiKey: try await askAPI(question, turnIndex: turnIndex)
                }
                if stop == "refusal" {
                    failure = "Claude declined to answer this one."
                } else if stop == "max_tokens" {
                    failure = "Answer was cut off (hit max tokens)."
                }
            } catch {
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                failure = cancelled ? "Stopped." : error.localizedDescription
            }
            guard generation == self.generation else { return }   // session was ended mid-stream
            update(turnIndex) { $0.error = failure; $0.done = true; $0.status = nil }
            isBusy = false
        }
    }

    /// Subscription: the Claude Code process keeps the conversation, so only the new question is sent.
    private func askClaudeCode(_ question: String, turnIndex: Int) async throws -> String? {
        let client = claudeCode ?? ClaudeCodeClient(system: system)
        claudeCode = client
        return try await client.send(question) { [weak self] event in
            self?.apply(event, to: turnIndex)
        }
    }

    /// API key: the full history is replayed on every request.
    private func askAPI(_ question: String, turnIndex: Int) async throws -> String? {
        guard let apiKey else { return nil }
        let checkpoint = history.count
        history.append(["role": "user", "content": question])
        let client = ClaudeClient(apiKey: apiKey, system: system)
        do {
            var stop: String?
            repeat {
                let result = try await client.stream(messages: history) { event in
                    self.apply(event, to: turnIndex)
                }
                stop = result.stopReason
                if stop == "refusal" { break }
                // Replay the assistant turn verbatim (thinking + tool blocks included).
                history.append(["role": "assistant", "content": result.content])
            } while stop == "pause_turn"   // server-side tool loop wants to keep going
            if stop == "refusal" { history.removeSubrange(min(checkpoint, history.count)...) }
            return stop
        } catch {
            // Roll back so the next question starts from a clean, valid history.
            history.removeSubrange(min(checkpoint, history.count)...)
            throw error
        }
    }

    private func apply(_ event: ClaudeClient.StreamEvent, to index: Int) {
        update(index) { turn in
            switch event {
            case .text(let piece):
                turn.answer += piece
                turn.status = nil
            case .status(let status):
                turn.status = status
            case .source(let title, let url):
                let source = Source(title: title, url: url)
                if !turn.sources.contains(source) { turn.sources.append(source) }
            }
        }
    }

    private func update(_ index: Int, _ change: (inout Turn) -> Void) {
        guard turns.indices.contains(index) else { return }   // session was ended mid-stream
        change(&turns[index])
    }

    private static func makeSystemPrompt() -> String {
        let date = Date().formatted(date: .complete, time: .omitted)
        return """
        You are a quick-lookup assistant inside a pop-up search box. Today is \(date).
        Answer directly and concisely — lead with the answer, then only the detail that helps. \
        Your reply is rendered as GitHub-flavored Markdown: use short paragraphs and bullet lists, \
        a table when comparing things across several attributes, and fenced code blocks tagged with \
        the language for any code or commands. Keep headings for long, multi-part answers. \
        LaTeX is not rendered, so write math with plain Unicode symbols. \
        Search the web when the question depends on current or specific facts you aren't sure of.
        """
    }
}
