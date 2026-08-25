import Foundation
import Testing
@testable import KibitzCore

@Suite("DeepSeekResponseParser")
struct DeepSeekResponseParserTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func parse(_ name: String, status: Int = 200) throws -> CheckResponse {
        try DeepSeekResponseParser.parse(
            fixture(name), status: status, model: .flash, apiDurationMS: 640
        )
    }

    @Test("reads the verdict out of the assistant message")
    func parsesErrorResponse() throws {
        let response = try parse("deepseek-error-response")

        #expect(response.verdict.outcome == .error)
        #expect(response.verdict.category == .wordChoice)
        #expect(response.verdict.severity == .high)
        #expect(response.verdict.corrected == "I am 20 years old and I have worked here since 2020.")
        #expect(response.verdict.whyL1.contains("Wiek"))
    }

    @Test("parses a correct sentence as ok")
    func parsesOkResponse() throws {
        let response = try parse("deepseek-ok-response")

        #expect(response.verdict.outcome == .ok)
        #expect(response.verdict.category == .noIssue)
        #expect(response.verdict.whyL1.isEmpty)
    }

    @Test("unwraps a markdown fence, which JSON mode does not rule out")
    func parsesFencedResponse() throws {
        let response = try parse("deepseek-fenced-response")

        #expect(response.verdict.outcome == .ok)
        #expect(response.verdict.corrected == "I pushed the fix to main and the pipeline is green.")
    }

    @Test("reports what the cache served, since that is what decides the bill")
    func reportsCacheUsage() throws {
        let warm = try parse("deepseek-error-response")
        #expect(warm.cacheReadTokens == 1408)
        #expect(warm.uncachedInputTokens == 24)

        let cold = try parse("deepseek-ok-response")
        #expect(cold.cacheReadTokens == 0)
        #expect(cold.uncachedInputTokens == 1432)
    }

    @Test("costs a fraction of a cent on a warm cache, and more on a cold one")
    func computesCost() throws {
        let warm = try parse("deepseek-error-response")
        let cold = try parse("deepseek-ok-response")

        // 1408 cached + 24 fresh in, 54 out, at flash list prices.
        #expect(abs(warm.costUSD - 0.000101552) < 0.000_000_1)
        // The same check with nothing cached costs several times more, which is
        // why the system prompt has to stay byte-identical between calls.
        #expect(cold.costUSD > warm.costUSD * 5)
    }

    @Test("carries the measured round trip through")
    func reportsTiming() throws {
        #expect(try parse("deepseek-ok-response").apiDurationMS == 640)
    }

    @Test("an empty reply is a named condition the provider can retry, not a crash")
    func reportsEmptyContent() throws {
        #expect(throws: DeepSeekError.emptyContent) {
            try parse("deepseek-empty-content")
        }
    }

    @Test("a reply that is not JSON is a skipped check, not a crash")
    func rejectsNonJSONContent() throws {
        let payload = #"{"choices":[{"message":{"content":"I'm not sure what you mean."}}]}"#

        #expect(throws: DeepSeekError.self) {
            try DeepSeekResponseParser.parse(
                Data(payload.utf8), status: 200, model: .flash, apiDurationMS: 1
            )
        }
    }

    @Test("a rejected key is reported as a rejected key, not as a status code")
    func mapsAuthenticationFailure() throws {
        #expect(throws: DeepSeekError.unauthorized) {
            try parse("deepseek-api-error", status: 401)
        }
    }

    @Test("the failures worth naming each get their own case")
    func mapsTheFailuresWorthNaming() {
        #expect(DeepSeekResponseParser.failure(status: 401, message: "") == .unauthorized)
        #expect(DeepSeekResponseParser.failure(status: 402, message: "") == .insufficientBalance)
        #expect(DeepSeekResponseParser.failure(status: 429, message: "") == .rateLimited)
        #expect(
            DeepSeekResponseParser.failure(status: 503, message: "overloaded")
                == .serverError(status: 503, message: "overloaded")
        )
    }

    @Test("carries DeepSeek's own explanation of a failure rather than dropping it")
    func surfacesTheAPIMessage() throws {
        do {
            _ = try parse("deepseek-api-error", status: 500)
            Issue.record("expected a failure")
        } catch DeepSeekError.serverError(_, let message) {
            #expect(message.contains("Authentication Fails"))
        }
    }
}
