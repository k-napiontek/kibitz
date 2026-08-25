import Foundation

public enum ClaudeCodeParseError: Error, Equatable {
    case cliReportedError(String)
    case missingResult
    case resultWasNotJSON(String)
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
            let inputTokens: Int?
        }
        let isError: Bool?
        let result: String?
        let totalCostUsd: Double?
        let durationApiMs: Int?
        let usage: Usage?
    }

    /// The CLI's own description of what went wrong, when it failed but still
    /// produced its JSON envelope.
    public static func reportedMessage(in data: Data) -> String? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let wrapper = try? decoder.decode(Wrapper.self, from: data),
              let result = wrapper.result, !result.isEmpty
        else { return nil }
        return result
    }

    public static func parse(_ data: Data) throws -> CheckResponse {
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

        guard let verdict = VerdictDecoder.decode(from: result) else {
            throw ClaudeCodeParseError.resultWasNotJSON(result)
        }

        return CheckResponse(
            verdict: verdict,
            costUSD: wrapper.totalCostUsd ?? 0,
            apiDurationMS: wrapper.durationApiMs ?? 0,
            cacheReadTokens: wrapper.usage?.cacheReadInputTokens ?? 0,
            uncachedInputTokens: wrapper.usage?.inputTokens ?? 0
        )
    }
}
