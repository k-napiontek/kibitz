import Foundation
import Testing
@testable import KibitzCore

@Suite("ClaudeCodeResponseParser")
struct ClaudeCodeResponseParserTests {

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    @Test("parses a real error response captured from the CLI")
    func parsesErrorResponse() throws {
        let response = try ClaudeCodeResponseParser.parse(fixture("cli-error-response"))

        #expect(response.verdict.outcome == .error)
        #expect(response.verdict.category == .wordChoice)
        #expect(response.verdict.severity == .high)
        #expect(response.verdict.corrected == "I am 20 years old and I have worked here since 2020.")
        #expect(response.verdict.whyL1.contains("Wiek"))
    }

    @Test("parses a real ok response")
    func parsesOkResponse() throws {
        let response = try ClaudeCodeResponseParser.parse(fixture("cli-ok-response"))

        #expect(response.verdict.outcome == .ok)
        #expect(response.verdict.category == .noIssue)
        #expect(response.verdict.whyL1.isEmpty)
    }

    @Test("unwraps a markdown fence, which the model sometimes adds despite the prompt")
    func parsesFencedResponse() throws {
        let response = try ClaudeCodeResponseParser.parse(fixture("cli-fenced-response"))

        #expect(response.verdict.outcome == .ok)
        #expect(response.verdict.corrected == "I pushed the fix to main and the pipeline is green.")
    }

    @Test("carries the cost and timing through so quota burn is measured, not estimated")
    func reportsUsage() throws {
        let response = try ClaudeCodeResponseParser.parse(fixture("cli-ok-response"))

        #expect(response.costUSD > 0)
        #expect(response.apiDurationMS > 0)
        #expect(response.cacheReadTokens > 0)
    }

    @Test("a reply that is not JSON is a skipped check, not a crash")
    func rejectsNonJSONResult() throws {
        let payload = #"{"is_error":false,"result":"I'm not sure what you mean.","total_cost_usd":0.01}"#

        #expect(throws: ClaudeCodeParseError.self) {
            try ClaudeCodeResponseParser.parse(Data(payload.utf8))
        }
    }

    @Test("an error reported by the CLI is surfaced, not silently parsed")
    func surfacesCLIError() throws {
        let payload = #"{"is_error":true,"result":"Credit balance too low","total_cost_usd":0}"#

        #expect(throws: ClaudeCodeParseError.self) {
            try ClaudeCodeResponseParser.parse(Data(payload.utf8))
        }
    }
}
