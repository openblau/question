import Foundation

/// Talks to Claude through the user's Claude subscription by driving the Claude Code CLI
/// (`claude -p`) in headless stream-json mode. The CLI owns the login, so no key is needed.
///
/// One process is one conversation: it stays alive across follow-ups and holds the history in
/// its own memory. `--no-session-persistence` keeps the transcript off disk; `terminate()` drops it.
@MainActor
final class ClaudeCodeClient {
    typealias StreamEvent = ClaudeClient.StreamEvent
    typealias APIError = ClaudeClient.APIError

    /// Finds the `claude` binary. GUI apps don't inherit the shell's PATH, so check the usual spots first.
    static let executable: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to asking a login shell.
        let shell = Process()
        let out = Pipe()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }()

    static let notInstalled = "Claude Code isn't installed. Install it and run `claude` once to log in, "
        + "or switch to an API key from the menu bar icon."

    private let system: String
    private var process: Process?
    private var stdin: FileHandle?
    private var reader: Task<Void, Never>?

    // State for the turn in flight.
    private var onEvent: ((StreamEvent) -> Void)?
    private var continuation: CheckedContinuation<String?, Error>?
    private var interrupted = false
    private var emittedText = false

    init(system: String) {
        self.system = system
    }

    /// Sends one user message and streams the reply. Returns the stop reason.
    func send(_ question: String, onEvent: @escaping (StreamEvent) -> Void) async throws -> String? {
        try launchIfNeeded()
        self.onEvent = onEvent
        interrupted = false
        emittedText = false
        defer { self.onEvent = nil }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.write(["type": "user", "message": ["role": "user", "content": question]])
            }
        } onCancel: {
            Task { @MainActor in self.interrupt() }
        }
    }

    /// Stops the reply in flight but keeps the conversation.
    func interrupt() {
        guard continuation != nil, !interrupted else { return }
        interrupted = true
        write(["type": "control_request", "request_id": UUID().uuidString, "request": ["subtype": "interrupt"]])
    }

    /// Ends the conversation: kills the process, and its in-memory history with it.
    func terminate() {
        reader?.cancel()
        reader = nil
        process?.terminate()
        process = nil
        stdin = nil
        finish(.failure(CancellationError()))
    }

    // MARK: Process

    private func launchIfNeeded() throws {
        if let process, process.isRunning { return }
        guard let executable = Self.executable else { throw APIError(message: Self.notInstalled) }

        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--no-session-persistence",                    // incognito: no transcript on disk
            "--setting-sources", "", "--strict-mcp-config", // ignore the user's hooks, CLAUDE.md, MCP servers
            "--tools", "WebSearch", "--allowedTools", "WebSearch",
            "--system-prompt", system,
            "--model", ClaudeClient.model, "--effort", ClaudeClient.effort,
        ]
        // Drop API credentials from the environment so the CLI bills the subscription, not a key.
        var environment = ProcessInfo.processInfo.environment
        environment["ANTHROPIC_API_KEY"] = nil
        environment["ANTHROPIC_AUTH_TOKEN"] = nil
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        self.process = process
        stdin = input.fileHandleForWriting
        let lines = output.fileHandleForReading.bytes.lines
        reader = Task { [weak self] in
            do {
                for try await line in lines { self?.handle(line) }
            } catch {}
            guard !Task.isCancelled else { return }
            // The process went away mid-conversation.
            self?.process = nil
            self?.finish(.failure(APIError(message:
                "Claude Code exited unexpectedly. Run `claude` in Terminal to check that you're logged in.")))
        }
    }

    private func write(_ object: [String: Any]) {
        guard let stdin, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do { try stdin.write(contentsOf: data) } catch {
            finish(.failure(APIError(message: "Couldn't reach Claude Code.")))
        }
    }

    private func finish(_ result: Result<String?, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    // MARK: Events

    private func handle(_ line: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { break }
            handleStream(event)

        case "user":
            // A finished web search: surface its links as sources.
            guard let result = object["tool_use_result"] as? [String: Any],
                  let results = result["results"] as? [Any] else { break }
            onEvent?(.status("Reading results…"))
            for case let group as [String: Any] in results {
                for case let hit as [String: Any] in group["content"] as? [Any] ?? [] {
                    if let url = hit["url"] as? String {
                        onEvent?(.source(title: hit["title"] as? String ?? url, url: url))
                    }
                }
            }

        case "result":
            if interrupted {
                finish(.failure(CancellationError()))
            } else if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
                let message = object["result"] as? String ?? "Claude Code reported an error."
                finish(.failure(APIError(message: message)))
            } else {
                finish(.success(object["stop_reason"] as? String))
            }

        default: break
        }
    }

    private func handleStream(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "message_start":
            // Text that resumes after a search starts a new paragraph.
            if emittedText { onEvent?(.text("\n\n")) }
        case "content_block_start":
            switch (event["content_block"] as? [String: Any])?["type"] as? String {
            case "thinking": onEvent?(.status("Thinking…"))
            case "tool_use": onEvent?(.status("Searching the web…"))
            default: break
            }
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let piece = delta["text"] as? String, !piece.isEmpty else { break }
            emittedText = true
            onEvent?(.text(piece))
        default: break
        }
    }
}
