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
    var focusTick = 0

    @ObservationIgnored private var history: [[String: Any]] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var system = ChatSession.makeSystemPrompt()

    init() {
        apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
            ?? Keychain.read()
    }

    var needsKey: Bool { apiKey == nil }

    /// Saves to the Keychain first; the key is only used if that succeeds.
    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try Keychain.save(trimmed)
        apiKey = trimmed
    }

    func forgetKey() {
        Keychain.delete()
        apiKey = nil
        end()
    }

    /// Ends the session: cancels any request and drops every message from memory.
    func end() {
        task?.cancel()
        task = nil
        turns = []
        history = []
        isBusy = false
        system = Self.makeSystemPrompt()
    }

    func stop() { task?.cancel() }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy, let apiKey else { return }

        turns.append(Turn(question: question))
        let turnIndex = turns.count - 1
        let checkpoint = history.count
        history.append(["role": "user", "content": question])
        isBusy = true

        let client = ClaudeClient(apiKey: apiKey, system: system)
        task = Task { [weak self] in
            guard let self else { return }
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

                if stop == "refusal" {
                    history.removeSubrange(checkpoint...)
                    update(turnIndex) { $0.error = "Claude declined to answer this one." }
                } else if stop == "max_tokens" {
                    update(turnIndex) { $0.error = "Answer was cut off (hit max tokens)." }
                }
            } catch {
                // Roll back so the next question starts from a clean, valid history.
                history.removeSubrange(checkpoint...)
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                update(turnIndex) { $0.error = cancelled ? "Stopped." : error.localizedDescription }
            }
            update(turnIndex) { $0.done = true; $0.status = nil }
            isBusy = false
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
        Use short paragraphs or bullet lists; avoid headings. \
        Search the web when the question depends on current or specific facts you aren't sure of.
        """
    }
}
