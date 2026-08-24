import Foundation
import Testing
@testable import KibitzCore

@Suite("Subprocess")
struct SubprocessTests {

    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test("returns stdout for a command that succeeds")
    func returnsStdout() async throws {
        let result = try await Subprocess.run(
            executable: shell, arguments: ["-c", "printf hello"], timeout: .seconds(5)
        )

        #expect(String(decoding: result.stdout, as: UTF8.self) == "hello")
        #expect(result.exitCode == 0)
    }

    @Test("a command that outruns the timeout says so, rather than failing to parse later")
    func reportsTimeoutDistinctly() async throws {
        do {
            _ = try await Subprocess.run(
                executable: shell,
                arguments: ["-c", "printf partial; sleep 30"],
                timeout: .milliseconds(700)
            )
            Issue.record("expected a timeout")
        } catch let error as SubprocessError {
            guard case .timedOut(_, let bytes, _) = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
            // The bug this pins down: partial output used to be returned as if
            // it were a whole response, surfacing as a confusing parse failure.
            #expect(bytes >= 0)
        }
    }

    @Test("a non-zero exit is surfaced with its stderr, not silently returned")
    func surfacesNonZeroExit() async throws {
        do {
            _ = try await Subprocess.run(
                executable: shell,
                arguments: ["-c", "echo boom >&2; exit 3"],
                timeout: .seconds(5)
            )
            Issue.record("expected a failure")
        } catch let error as SubprocessError {
            guard case .nonZeroExit(let code, let stderr) = error else {
                Issue.record("expected .nonZeroExit, got \(error)")
                return
            }
            #expect(code == 3)
            #expect(stderr.contains("boom"))
        }
    }

    @Test("a child that floods stderr does not deadlock the read")
    func doesNotDeadlockOnLargeStderr() async throws {
        // A pipe buffer is about 64KB. If stderr is never drained, the child
        // blocks forever on write and stdout never reaches EOF.
        let result = try await Subprocess.run(
            executable: shell,
            arguments: ["-c", "yes x | head -c 300000 >&2; printf done"],
            timeout: .seconds(10)
        )

        #expect(String(decoding: result.stdout, as: UTF8.self) == "done")
    }

    @Test("concurrent runs all finish and keep their output separate")
    func survivesConcurrentRuns() async throws {
        // Note: this does NOT reproduce the corpus-run stall. It was written to,
        // and passed even against the pre-fix code, so the pool-starvation theory
        // is unproven. Kept because concurrent correctness is worth pinning.
        let outputs = await withTaskGroup(of: String?.self) { group in
            for i in 0..<8 {
                group.addTask {
                    let result = try? await Subprocess.run(
                        executable: URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", "sleep 0.2; printf run\(i)"],
                        timeout: .seconds(20)
                    )
                    return result.map { String(decoding: $0.stdout, as: UTF8.self) }
                }
            }
            var seen: [String?] = []
            for await o in group { seen.append(o) }
            return seen
        }

        #expect(outputs.count == 8)
        #expect(outputs.allSatisfy { $0?.hasPrefix("run") == true })
    }
}
