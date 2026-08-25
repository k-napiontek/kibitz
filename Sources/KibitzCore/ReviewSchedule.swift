import Foundation

public enum ReviewDecision: Sendable, Equatable {
    case due
    case notYet
    /// Record now as the starting point and stay quiet. The first launch, and
    /// any stored date that cannot be true.
    case setBaseline
}

/// When the weekly review is due.
///
/// Nothing here counts down. Every answer is recomputed from a stored date and
/// the current wall clock, so a laptop that spent a week asleep comes back due
/// rather than having missed its slot, and the tick interval only bounds how
/// late the window can be.
public enum ReviewSchedule {

    public static let interval: TimeInterval = 7 * 24 * 3600

    public static func decide(lastReview: Date?, now: Date) -> ReviewDecision {
        guard let lastReview else { return .setBaseline }
        // A restored backup or a clock that moved. Rebasing rewrites it with a
        // sane value; leaving it alone freezes the review until the clock catches up.
        guard lastReview <= now else { return .setBaseline }
        return now.timeIntervalSince(lastReview) >= interval ? .due : .notYet
    }

    /// A week, or back to the last review if that was longer ago. Coming back
    /// from a month away should not silently drop three weeks of mistakes, which
    /// are exactly the ones worth seeing.
    public static func windowStart(lastReview: Date?, now: Date) -> Date {
        let week = now.addingTimeInterval(-interval)
        guard let lastReview, lastReview < week else { return week }
        return lastReview
    }
}

/// The review stamp, persisted. The same shape as `BackendSettings`: injected
/// defaults, a stable key, and a read that falls back rather than trapping.
public struct ReviewSettings {

    public static let lastReviewKey = "review.lastShown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stored as seconds since 1970 rather than as a `Date`, so a due review can
    /// be forced with `defaults write` while testing the window by hand.
    public var lastReview: Date? {
        get {
            guard let stored = defaults.object(forKey: Self.lastReviewKey) as? Double,
                  stored > 0
            else { return nil }
            return Date(timeIntervalSince1970: stored)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: Self.lastReviewKey)
                return
            }
            defaults.set(newValue.timeIntervalSince1970, forKey: Self.lastReviewKey)
        }
    }
}
