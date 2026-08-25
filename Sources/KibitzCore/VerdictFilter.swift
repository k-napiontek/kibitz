import Foundation

public struct FilterConfig: Sendable, Codable, Equatable {
    public var mutedCategories: Set<Category>
    public var muteLowSeverity: Bool

    public init(mutedCategories: Set<Category>, muteLowSeverity: Bool) {
        self.mutedCategories = mutedCategories
        self.muteLowSeverity = muteLowSeverity
    }

    /// Mechanical slips are muted so they never interrupt typing. They are
    /// still written to the log, so the weekly digest can still see them.
    public static let `default` = FilterConfig(
        mutedCategories: [.spelling, .punctuation, .capitalization],
        muteLowSeverity: false
    )
}

public enum FilterReason: String, Sendable, Equatable {
    case sentenceIsCorrect
    case categoryMuted
    case lowSeverity
}

public enum FilterOutcome: Sendable, Equatable {
    case show
    case logOnly(FilterReason)
}

/// Decides what interrupts the writer. Never decides what gets recorded: everything
/// reaches the log regardless, or the weekly digest would go blind to whole
/// classes of mistake.
public struct VerdictFilter: Sendable {
    private let config: FilterConfig

    public init(config: FilterConfig) {
        self.config = config
    }

    /// The muting rules apply to `.automatic` only, because interrupting is the
    /// only thing they exist to prevent, and a hotkey press is not an
    /// interruption. It is a question, and a question is owed an answer.
    ///
    /// This distinction is not academic. `category` is one word, but `corrected`
    /// is a whole rewritten sentence, and the two routinely disagree about how
    /// much changed: a verdict labelled `capitalization` on
    /// `explain this is scc in the openshift` also dropped a stray article.
    /// Reading the label and discarding the sentence answered a deliberate press
    /// with silence, for the majority of everything that was ever asked.
    public func apply(_ verdict: Verdict, source: CaptureSource) -> FilterOutcome {
        guard verdict.outcome == .error else { return .logOnly(.sentenceIsCorrect) }
        guard source == .automatic else { return .show }
        if config.mutedCategories.contains(verdict.category) { return .logOnly(.categoryMuted) }
        if config.muteLowSeverity, verdict.severity == .low { return .logOnly(.lowSeverity) }
        return .show
    }
}
