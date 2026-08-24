import Foundation

/// Appends timestamped stage markers to a file.
///
/// The unified log is not readable in every context, which made "it just hangs"
/// impossible to diagnose. A plain file always is. Sentence content is never
/// written here, only lengths and stage names.
enum DiagnosticLog {

    static let url = URL.applicationSupportDirectory
        .appending(path: "kibitz", directoryHint: .isDirectory)
        .appending(path: "diagnostics.log")

    private static let queue = DispatchQueue(label: "com.knapiontek.kibitz.diag")

    static func write(_ message: String) {
        queue.async {
            let stamp = Date().formatted(date: .omitted, time: .standard)
            let line = "\(stamp)  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
