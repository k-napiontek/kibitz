import Foundation

public enum ClaudeCodeParseError: Error, Equatable {
    case cliReportedError(String)
    case missingResult
    case resultWasNotJSON(String)
}

public struct ClaudeCodeResponse: Sendable, Equatable {
    public let verdict: Verdict
    public let costUSD: Double
    public let apiDurationMS: Int
    public let cacheReadTokens: Int
}

/// Turns `claude -p --output-format json` output into a `Verdict`.
///
/// This path has no structured-output guarantee, so the model does sometimes
/// ignore the instruction not to fence its reply. Observed in practice, hence
/// the unwrapping below rather than a strict decode.
public enum ClaudeCodeResponseParser {

    private struct Wrapper: Decodable {
        struct Usage: Decodable {
            let cacheReadInputTokens: Int?
        }
        let isError: Bool?
        let result: String?
        let totalCostUsd: Double?
        let durationApiMs: Int?
        let usage: Usage?
    }

    public static func parse(_ data: Data) throws -> ClaudeCodeResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let wrapper = try? decoder.decode(Wrapper.self, from: data),
              let result = wrapper.result
        else {
            throw ClaudeCodeParseError.missingResult
        }

        if wrapper.isError == true {
            throw ClaudeCodeParseError.cliReportedError(result)
        }

        guard let verdict = decodeVerdict(from: result) else {
            throw ClaudeCodeParseError.resultWasNotJSON(result)
        }

        return ClaudeCodeResponse(
            verdict: verdict,
            costUSD: wrapper.totalCostUsd ?? 0,
            apiDurationMS: wrapper.durationApiMs ?? 0,
            cacheReadTokens: wrapper.usage?.cacheReadInputTokens ?? 0
        )
    }

    /// Tries the reply as-is, then as the outermost `{...}` span. The second
    /// attempt is what survives a markdown fence or a stray sentence.
    private static func decodeVerdict(from result: String) -> Verdict? {
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
