import Foundation

/// Why a DeepSeek check did not produce a verdict.
///
/// Cases exist per fix, not per status code: the app turns each one into a
/// sentence naming what to do about it.
public enum DeepSeekError: Error, Equatable {
    case unauthorized
    case insufficientBalance
    case rateLimited
    case serverError(status: Int, message: String)
    /// Documented as an occasional behaviour of JSON mode.
    case emptyContent
    case replyWasNotJSON(String)
    case timedOut
    case transport(String)
}

/// Turns a chat-completions response into a `CheckResponse`.
public enum DeepSeekResponseParser {

    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message?
        }
        struct Usage: Decodable {
            let promptCacheHitTokens: Int?
            let promptCacheMissTokens: Int?
            let completionTokens: Int?
        }
        struct APIError: Decodable {
            let message: String?
        }
        let choices: [Choice]?
        let usage: Usage?
        let error: APIError?
    }

    public static func parse(
        _ data: Data,
        status: Int,
        model: DeepSeekModel,
        apiDurationMS: Int
    ) throws -> CheckResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try? decoder.decode(Envelope.self, from: data)

        guard status == 200 else {
            // DeepSeek explains itself in the body. Prefer that over the code,
            // the way the CLI path prefers the CLI's own message.
            throw failure(
                status: status,
                message: envelope?.error?.message
                    ?? String(decoding: data, as: UTF8.self).prefix(200).description
            )
        }

        guard let envelope else {
            throw DeepSeekError.replyWasNotJSON(
                String(decoding: data, as: UTF8.self).prefix(200).description
            )
        }

        let content = envelope.choices?.first?.message?.content ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekError.emptyContent
        }
        guard let verdict = VerdictDecoder.decode(from: content) else {
            throw DeepSeekError.replyWasNotJSON(content)
        }

        let usage = envelope.usage
        let cacheHit = usage?.promptCacheHitTokens ?? 0
        let cacheMiss = usage?.promptCacheMissTokens ?? 0
        let output = usage?.completionTokens ?? 0
        let price = model.pricing
        let cost = (Double(cacheHit) * price.cacheHit
            + Double(cacheMiss) * price.cacheMiss
            + Double(output) * price.output) / 1_000_000

        return CheckResponse(
            verdict: verdict,
            costUSD: cost,
            apiDurationMS: apiDurationMS,
            cacheReadTokens: cacheHit,
            uncachedInputTokens: cacheMiss
        )
    }

    static func failure(status: Int, message: String) -> DeepSeekError {
        switch status {
        case 401: .unauthorized
        case 402: .insufficientBalance
        case 429: .rateLimited
        default: .serverError(status: status, message: message)
        }
    }
}
