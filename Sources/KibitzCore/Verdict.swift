import Foundation

/// The kind of mistake, as reported by the model.
///
/// The raw values are the JSON wire format and the strings stored in the
/// mistake log, so they must stay stable once data exists.
public enum Category: String, Sendable, Codable, CaseIterable, Equatable {
    case article
    case tense
    case preposition
    case wordOrder = "word-order"
    case wordChoice = "word-choice"
    case naturalness
    case agreement
    case spelling
    case punctuation
    case capitalization
    case noIssue = "none"
}

public enum Severity: String, Sendable, Codable, Equatable {
    case high
    case low
}

public struct Verdict: Sendable, Codable, Equatable {
    public enum Outcome: String, Sendable, Codable, Equatable {
        case ok
        case error
    }

    public let outcome: Outcome
    public let category: Category
    public let severity: Severity
    public let corrected: String
    public let whyL1: String

    public init(
        outcome: Outcome,
        category: Category,
        severity: Severity,
        corrected: String,
        whyL1: String
    ) {
        self.outcome = outcome
        self.category = category
        self.severity = severity
        self.corrected = corrected
        self.whyL1 = whyL1
    }

    private enum CodingKeys: String, CodingKey {
        case outcome = "verdict"
        case category
        case severity
        case corrected
        case whyL1 = "why_l1"
    }
}
