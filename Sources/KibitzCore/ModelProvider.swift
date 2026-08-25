import Foundation

/// What one check cost and how long it took, alongside the verdict.
///
/// Carried by every backend so quota burn is measured rather than estimated,
/// and so the corpus harness can report the same numbers whichever backend ran.
public struct CheckResponse: Sendable, Equatable {
    public let verdict: Verdict
    public let costUSD: Double
    public let apiDurationMS: Int
    public let cacheReadTokens: Int
    /// Input tokens the cache did not serve. The ratio against
    /// `cacheReadTokens` is what decides the bill on both backends.
    public let uncachedInputTokens: Int

    public init(
        verdict: Verdict,
        costUSD: Double,
        apiDurationMS: Int,
        cacheReadTokens: Int,
        uncachedInputTokens: Int = 0
    ) {
        self.verdict = verdict
        self.costUSD = costUSD
        self.apiDurationMS = apiDurationMS
        self.cacheReadTokens = cacheReadTokens
        self.uncachedInputTokens = uncachedInputTokens
    }
}

/// The seam between the pipeline and whatever is judging sentences.
///
/// The subscription backend and the direct API backend differ by an order of
/// magnitude in latency, which is why automatic mode is a capability of the
/// provider rather than a user setting.
public protocol ModelProvider: Sendable {
    /// Named for the menu and for the corpus report header, so a run's output
    /// says which backend produced it.
    var displayName: String { get }
    var supportsAutomaticMode: Bool { get }
    /// Returns the full response. `check` is the pipeline's view of the same
    /// call; the corpus and check harnesses want the cost and timing too.
    func run(sentence: String, previous: String?) async throws -> CheckResponse
}

extension ModelProvider {
    public func check(sentence: String, previous: String?) async throws -> Verdict {
        try await run(sentence: sentence, previous: previous).verdict
    }
}
