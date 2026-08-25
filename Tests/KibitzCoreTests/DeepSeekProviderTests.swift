import Foundation
import Testing
@testable import KibitzCore

@Suite("DeepSeekProvider")
struct DeepSeekProviderTests {

    private let prompt = "RENDERED PROMPT for a Polish-speaking engineer. Reply with json."
    private var provider: DeepSeekProvider {
        DeepSeekProvider(apiKey: "sk-test-key", systemPrompt: prompt, model: .flash)
    }

    private func body(sentence: String, previous: String? = nil) throws -> [String: Any] {
        let data = try provider.requestBody(sentence: sentence, previous: previous)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "request body was not a JSON object"
        )
    }

    private func messages(in body: [String: Any]) throws -> [[String: String]] {
        try #require(body["messages"] as? [[String: String]], "messages missing")
    }

    @Test("the API backend is fast enough to be a candidate for automatic mode")
    func supportsAutomaticMode() {
        #expect(provider.supportsAutomaticMode)
    }

    @Test("pins a V4 model id, never a retired alias")
    func pinsTheModel() throws {
        #expect(try body(sentence: "Hello there.")["model"] as? String == "deepseek-v4-flash")

        let pro = DeepSeekProvider(apiKey: "k", systemPrompt: prompt, model: .pro)
        let proBody = try JSONSerialization.jsonObject(
            with: pro.requestBody(sentence: "Hello there.", previous: nil)
        ) as? [String: Any]
        #expect(proBody?["model"] as? String == "deepseek-v4-pro")

        for model in DeepSeekModel.allCases {
            #expect(model.rawValue != "deepseek-chat")
            #expect(model.rawValue != "deepseek-reasoner")
        }
    }

    @Test("asks for JSON output, which the parser depends on")
    func requestsJSONOutput() throws {
        let format = try #require(body(sentence: "Hello there.")["response_format"] as? [String: String])

        #expect(format["type"] == "json_object")
    }

    @Test("caps the output so the JSON object cannot stop mid-string")
    func capsOutputLength() throws {
        #expect(try body(sentence: "Hello there.")["max_tokens"] as? Int == 300)
    }

    @Test("turns thinking off, or the answer never fits in the budget")
    func disablesThinking() throws {
        let thinking = try #require(
            body(sentence: "Hello there.")["thinking"] as? [String: String],
            "no thinking field: V4 thinks by default and spends max_tokens on reasoning"
        )

        #expect(thinking["type"] == "disabled")
    }

    @Test("does not stream, so the parser sees one whole body")
    func doesNotStream() throws {
        #expect(try body(sentence: "Hello there.")["stream"] as? Bool == false)
    }

    @Test("repeated checks of one sentence must not disagree with themselves")
    func pinsTemperature() throws {
        #expect(try body(sentence: "Hello there.")["temperature"] as? Double == 0)
    }

    @Test("the system prompt leads and is sent verbatim, so the prefix cache hits it")
    func systemPromptIsTheCachedPrefix() throws {
        let first = try messages(in: body(sentence: "I have 20 years.")).first

        #expect(first?["role"] == "system")
        #expect(first?["content"] == prompt)

        // Same prefix for a different sentence, or the cache never hits.
        let other = try messages(in: body(sentence: "The tests was failing.")).first
        #expect(other?["content"] == prompt)
    }

    @Test("sends the literal word NONE when there is no preceding sentence")
    func formatsInputWithoutContext() throws {
        let user = try messages(in: body(sentence: "I have 20 years.")).last

        #expect(user?["role"] == "user")
        #expect(user?["content"] == "NONE\n---\nI have 20 years.")
    }

    @Test("passes the preceding sentence as context above the separator")
    func formatsInputWithContext() throws {
        let user = try messages(
            in: body(sentence: "The tests was failing.", previous: "We merged the refactor.")
        ).last

        #expect(user?["content"] == "We merged the refactor.\n---\nThe tests was failing.")
    }

    @Test("authenticates with a bearer header and keeps the key out of the body")
    func authenticatesWithoutLeakingTheKey() throws {
        let request = try provider.urlRequest(sentence: "Hello there.", previous: nil)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains("sk-test-key"))
    }

    @Test("gives up rather than leaving the popup pending forever")
    func boundsTheWait() throws {
        let request = try provider.urlRequest(sentence: "Hello there.", previous: nil)

        #expect(request.timeoutInterval == 15)
    }

    @Test("names itself, so a corpus run says which backend produced the numbers")
    func namesItself() {
        #expect(provider.displayName.contains("deepseek-v4-flash"))
    }

    @Test("the shipped prompt satisfies what json_object mode requires of it")
    func bundledPromptEnablesJSONMode() throws {
        let rendered = try BundledPrompt.renderedSystemPrompt(for: .polish)

        // DeepSeek requires the word "json" in the prompt and works best with a
        // worked example. Losing either in a prompt edit breaks JSON mode
        // silently, so it is pinned here rather than discovered in production.
        #expect(rendered.localizedCaseInsensitiveContains("json"))
        #expect(rendered.contains("\"verdict\""))
    }

    @Test("pro costs more than flash on every axis, which is the trade being offered")
    func pricingReflectsTheTrade() {
        #expect(DeepSeekModel.pro.pricing.cacheHit > DeepSeekModel.flash.pricing.cacheHit)
        #expect(DeepSeekModel.pro.pricing.cacheMiss > DeepSeekModel.flash.pricing.cacheMiss)
        #expect(DeepSeekModel.pro.pricing.output > DeepSeekModel.flash.pricing.output)
    }
}
