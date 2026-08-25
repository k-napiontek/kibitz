import Foundation

/// Reads a `Verdict` out of whatever the model actually replied with.
///
/// Neither backend can guarantee a bare JSON object. The CLI has no structured
/// output at all, and DeepSeek's JSON mode is a strong hint rather than
/// constrained decoding. Both have been observed wrapping the object in a
/// markdown fence despite the prompt forbidding it, so tolerance lives here
/// once instead of in each parser.
public enum VerdictDecoder {

    /// Tries the reply as-is, then as the outermost `{...}` span. The second
    /// attempt is what survives a markdown fence or a stray sentence.
    public static func decode(from result: String) -> Verdict? {
        let decoder = JSONDecoder()
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if let verdict = try? decoder.decode(Verdict.self, from: Data(trimmed.utf8)) {
            return verdict
        }
        guard let open = trimmed.firstIndex(of: "{"),
              let close = trimmed.lastIndex(of: "}"),
              open < close
        else {
            return nil
        }
        let span = String(trimmed[open...close])
        return try? decoder.decode(Verdict.self, from: Data(span.utf8))
    }
}
