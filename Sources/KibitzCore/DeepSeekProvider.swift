import Foundation

/// The DeepSeek models kibitz will talk to.
///
/// The raw values are the wire model ids. `deepseek-chat` and
/// `deepseek-reasoner` are deliberately absent: those aliases were retired on
/// 2026-07-24 and now fail rather than falling back.
public enum DeepSeekModel: String, CaseIterable, Sendable {
    case flash = "deepseek-v4-flash"
    case pro = "deepseek-v4-pro"

    public var menuTitle: String {
        switch self {
        case .flash: "Flash - faster and cheaper"
        case .pro: "Pro - better judgement"
        }
    }

    /// List price per 1M tokens, in USD.
    ///
    /// These are the **peak** rates published in August 2026. DeepSeek bills
    /// off-peak at half of them, so a cost computed from this table is an upper
    /// bound, not an invoice. The API returns no cost of its own.
    struct Pricing {
        let cacheHit: Double
        let cacheMiss: Double
        let output: Double
    }

    var pricing: Pricing {
        switch self {
        case .flash: Pricing(cacheHit: 0.014, cacheMiss: 0.44, output: 1.32)
        case .pro: Pricing(cacheHit: 0.044, cacheMiss: 1.32, output: 3.96)
        }
    }
}

/// Judges sentences through DeepSeek's OpenAI-compatible chat endpoint, billed
/// to an API key rather than to a subscription.
///
/// This exists because the subscription path costs ~5 s and ~$0.031 per check.
/// Here the system prompt hits DeepSeek's automatic prefix cache, so a check is
/// on the order of $0.0001. Whether it is meaningfully *faster* is a property
/// of DeepSeek's endpoint on the day, which is why `kibitz-check` prints the
/// wall time on every run.
public struct DeepSeekProvider: ModelProvider {

    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!

    /// The documented guard against a JSON string that stops mid-object. A
    /// corrected sentence plus a one-line explanation is far under this.
    static let maxTokens = 300
    static let timeout: TimeInterval = 15

    private let apiKey: String
    private let systemPrompt: String
    private let model: DeepSeekModel
    private let baseURL: URL
    private let session: URLSession

    /// Takes an already-rendered prompt, like the subscription provider does,
    /// so both backends coach from the same artifact.
    public init(
        apiKey: String,
        systemPrompt: String,
        model: DeepSeekModel = .flash,
        baseURL: URL = DeepSeekProvider.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public var displayName: String { "DeepSeek API (\(model.rawValue))" }

    /// Fast enough to consider, unlike the subscription path. Whether it is
    /// fast enough in practice is a measurement, not a claim.
    public var supportsAutomaticMode: Bool { true }

    // MARK: - Request

    private struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable {
            let type: String
        }
        let model: String
        let messages: [Message]
        let maxTokens: Int
        let temperature: Double
        let stream: Bool
        let responseFormat: ResponseFormat

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
    }

    /// The system message is byte-identical on every call and comes first, so
    /// DeepSeek's automatic prefix cache matches it. Caching needs no request
    /// field, but it is best-effort and expires after hours to days, which is
    /// why the cost this provider reports varies between calls.
    ///
    /// `response_format: json_object` requires the word "json" somewhere in the
    /// prompt and works best with a worked example. `system-prompt.md` supplies
    /// both, and a test pins that so a prompt edit cannot quietly disable it.
    func requestBody(sentence: String, previous: String?) throws -> Data {
        let request = Request(
            model: model.rawValue,
            messages: [
                Request.Message(role: "system", content: systemPrompt),
                Request.Message(
                    role: "user",
                    content: CheckInput.format(sentence: sentence, previous: previous)
                )
            ],
            maxTokens: Self.maxTokens,
            // Sentence triage is a classification, not a creative task. Repeated
            // checks of the same sentence should not disagree with themselves.
            temperature: 0,
            stream: false,
            responseFormat: Request.ResponseFormat(type: "json_object")
        )
        return try JSONEncoder().encode(request)
    }

    func urlRequest(sentence: String, previous: String?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(sentence: sentence, previous: previous)
        return request
    }

    // MARK: - Call

    public func run(sentence: String, previous: String?) async throws -> CheckResponse {
        do {
            return try await attempt(sentence: sentence, previous: previous)
        } catch DeepSeekError.emptyContent {
            // DeepSeek documents JSON mode as occasionally returning empty
            // content. Behind a hotkey that reads as "nothing happened", which
            // is the worst outcome available, so it is worth one more call.
            return try await attempt(sentence: sentence, previous: previous)
        }
    }

    private func attempt(sentence: String, previous: String?) async throws -> CheckResponse {
        let request = try urlRequest(sentence: sentence, previous: previous)
        let started = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw DeepSeekError.timedOut
        } catch {
            throw DeepSeekError.transport(String(describing: error))
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return try DeepSeekResponseParser.parse(
            data,
            status: (response as? HTTPURLResponse)?.statusCode ?? 0,
            model: model,
            apiDurationMS: elapsed
        )
    }
}
