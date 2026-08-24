import Foundation

/// Runs sentences through the `claude` CLI, billed to the Claude Max
/// subscription rather than an API key.
///
/// Measured at roughly five seconds per check, because the CLI sends its own
/// system prompt and tool definitions on every invocation. Fine behind a
/// hotkey; far too slow to check sentences as they are typed.
public struct ClaudeCodeProvider: ModelProvider {
    private let systemPrompt: String
    private let model: String

    /// Takes an already-rendered prompt rather than a path, because the
    /// learner's language is substituted in before the backend ever sees it.
    public init(systemPrompt: String, model: String = "sonnet") {
        self.systemPrompt = systemPrompt
        self.model = model
    }

    public var supportsAutomaticMode: Bool { false }

    /// The prompt expects context above the separator and the sentence to
    /// judge below it. `NONE` keeps the shape constant when there is no
    /// preceding sentence, so the cached prefix stays stable.
    static func formatInput(sentence: String, previous: String?) -> String {
        let context = previous?.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = (context?.isEmpty == false ? context! : "NONE")
        return "\(head)\n---\n\(sentence)"
    }

    func arguments(for sentence: String, previous: String?) -> [String] {
        [
            "--print", Self.formatInput(sentence: sentence, previous: previous),
            "--model", model,
            "--system-prompt", systemPrompt,
            "--output-format", "json",
            "--strict-mcp-config",
            "--mcp-config", #"{"mcpServers":{}}"#,
            "--allowed-tools", "",
            "--no-session-persistence",
            "--max-turns", "1"
        ]
    }

    public func check(sentence: String, previous: String?) async throws -> Verdict {
        try await run(sentence: sentence, previous: previous).verdict
    }

    /// Returns the full response so callers can record real cost and latency
    /// rather than estimating them.
    public func run(sentence: String, previous: String?) async throws -> ClaudeCodeResponse {
        let output = try await Subprocess.run(
            executable: executableURL,
            arguments: arguments(for: sentence, previous: previous),
            timeout: .seconds(15)
        )
        return try ClaudeCodeResponseParser.parse(output)
    }

    private var executableURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".local/bin/claude")
    }
}

enum SubprocessError: Error, Equatable {
    case timedOut
    case launchFailed(String)
}

enum Subprocess {
    /// Runs a process to completion, killing it if it outruns the timeout.
    static func run(executable: URL, arguments: [String], timeout: Duration) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw SubprocessError.launchFailed(String(describing: error))
        }

        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()

        if data.isEmpty { throw SubprocessError.timedOut }
        return data
    }
}
