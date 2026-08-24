import Foundation

/// The seam between the pipeline and whatever is judging sentences.
///
/// The subscription backend and the direct API backend differ by an order of
/// magnitude in latency, which is why automatic mode is a capability of the
/// provider rather than a user setting.
public protocol ModelProvider: Sendable {
    var supportsAutomaticMode: Bool { get }
    func check(sentence: String, previous: String?) async throws -> Verdict
}
