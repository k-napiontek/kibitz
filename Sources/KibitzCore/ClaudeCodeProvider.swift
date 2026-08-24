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
        let result = try await Subprocess.run(
            executable: executableURL,
            arguments: arguments(for: sentence, previous: previous),
            timeout: .seconds(30),
            workingDirectory: try? Self.scratchWorkingDirectory(),
            environment: childEnvironment
        )
        return try ClaudeCodeResponseParser.parse(result.stdout)
    }

    /// An empty directory for the CLI to run in.
    ///
    /// This matters more than it looks. The `claude` CLI treats its working
    /// directory as a project and reads it at startup, and macOS attributes a
    /// child process's file access to the responsible parent - this app. Left to
    /// inherit whatever directory the .app was launched from, that produced
    /// permission prompts in kibitz's name for Photos and network volumes.
    /// An empty directory gives it nothing to read.
    static func scratchWorkingDirectory() throws -> URL {
        let directory = URL.applicationSupportDirectory
            .appending(path: "kibitz", directoryHint: .isDirectory)
            .appending(path: "cli-workdir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A GUI process can be launched with almost no environment. The CLI needs a
    /// usable PATH and HOME to find its own credentials, and returns
    /// "Not logged in" without them.
    private var childEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        let path = environment["PATH"] ?? ""
        if !path.contains("/usr/bin") {
            environment["PATH"] = path.isEmpty
                ? "/usr/bin:/bin:/usr/sbin:/sbin"
                : path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return environment
    }

    private var executableURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".local/bin/claude")
    }
}

public enum SubprocessError: Error, Equatable {
    case launchFailed(String)
    /// Carries what was actually received. Returning partial output as if it
    /// were whole surfaced later as a confusing parse failure instead.
    case timedOut(seconds: Double, bytesReceived: Int, stderr: String)
    case nonZeroExit(code: Int32, stderr: String)
}

struct SubprocessResult: Sendable {
    let stdout: Data
    let stderr: String
    let exitCode: Int32
}

enum Subprocess {
    /// Runs a process to completion, killing it if it outruns the timeout.
    ///
    /// Both pipes are drained concurrently. Draining only stdout lets a child
    /// that writes more than a pipe buffer to stderr block forever on write,
    /// so stdout never reaches EOF and the call hangs until the watchdog fires.
    static func run(
        executable: URL,
        arguments: [String],
        timeout: Duration,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> SubprocessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // A GUI app's children inherit a stdin they can block on forever.
        process.standardInput = FileHandle.nullDevice

        let started = Date()
        do {
            try process.run()
        } catch {
            throw SubprocessError.launchFailed(String(describing: error))
        }

        let killed = FlagBox()
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning {
                killed.value = true
                process.terminate()
            }
        }
        defer { watchdog.cancel() }

        // Both reads run concurrently, so neither pipe can back up on the other.
        async let outData = readToEnd(outPipe.fileHandleForReading)
        async let errData = readToEnd(errPipe.fileHandleForReading)
        let (out, err) = await (outData, errData)
        await waitForExit(process)
        let timedOut = killed.value

        let stderrText = String(decoding: err, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if timedOut {
            throw SubprocessError.timedOut(
                seconds: Date().timeIntervalSince(started),
                bytesReceived: out.count,
                stderr: String(stderrText.prefix(500))
            )
        }
        guard process.terminationStatus == 0 else {
            throw SubprocessError.nonZeroExit(
                code: process.terminationStatus,
                stderr: String(stderrText.prefix(500))
            )
        }
        return SubprocessResult(
            stdout: out,
            stderr: stderrText,
            exitCode: process.terminationStatus
        )
    }
}

/// Waits off the cooperative pool. `waitUntilExit` blocks its thread, and
/// blocking pool threads starves the continuations that the pipe reads resume
/// on, which deadlocks as soon as a few of these run concurrently.
private func waitForExit(_ process: Process) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            continuation.resume()
        }
    }
}

/// Reads a pipe to EOF off the cooperative pool, since `readToEnd` blocks.
private func readToEnd(_ handle: FileHandle) async -> Data {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
        }
    }
}

/// Carries the watchdog's decision back to the caller.
private final class FlagBox: @unchecked Sendable {
    var value = false
}
