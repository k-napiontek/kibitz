import Foundation

/// One mistake, as it was recorded.
///
/// A `Verdict` is deliberately identity-free and timestamp-free: it is what the
/// model said about one sentence, nothing more. This is that verdict plus the
/// three things the check had in scope and used to drop on the floor - when it
/// happened, what was actually written, and where it was written.
public struct Mistake: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let at: Date
    public let category: Category
    public let severity: Severity
    /// The sentence as it was written. The front of an Anki card, and the only
    /// place the mistake itself survives - `Verdict` carries only the fix.
    public let original: String
    public let corrected: String
    public let whyL1: String
    /// The bundle id of the app it was written in, when the app reported one.
    public let app: String?
    /// Marked once the row has been exported to Anki. A mark, never a filter:
    /// the row stays visible so a second export is a choice, not a surprise.
    public let exported: Bool

    public init(
        id: Int64,
        at: Date,
        category: Category,
        severity: Severity,
        original: String,
        corrected: String,
        whyL1: String,
        app: String?,
        exported: Bool
    ) {
        self.id = id
        self.at = at
        self.category = category
        self.severity = severity
        self.original = original
        self.corrected = corrected
        self.whyL1 = whyL1
        self.app = app
        self.exported = exported
    }
}
