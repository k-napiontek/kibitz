import Foundation

/// One week of mistakes, grouped and ordered by what is worth studying.
///
/// A pure function over rows rather than an `ORDER BY`, because this is the part
/// of the feature most likely to be argued about and a SQL string is not
/// something a test can pin down.
public struct MistakeDigest: Sendable, Equatable {

    public struct Limits: Sendable, Equatable {
        public let maxGroups: Int
        public let maxItemsPerGroup: Int

        public init(maxGroups: Int, maxItemsPerGroup: Int) {
            self.maxGroups = maxGroups
            self.maxItemsPerGroup = maxItemsPerGroup
        }

        /// A weekly list you can finish in two minutes gets used. Three hundred
        /// rows gets closed, and then the habit is gone.
        public static let `default` = Limits(maxGroups: 5, maxItemsPerGroup: 8)
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public var id: Category { category }
        public let category: Category
        /// Every mistake in this category in the window, cards included and caps
        /// ignored. "You got articles wrong nine times" stays true whether or not
        /// you already made the card or the list stopped at eight.
        public let count: Int
        public let highSeverityCount: Int
        /// Only the ones that could still become a card.
        public let items: [Mistake]

        public init(category: Category, count: Int, highSeverityCount: Int, items: [Mistake]) {
            self.category = category
            self.count = count
            self.highSeverityCount = highSeverityCount
            self.items = items
        }
    }

    public let groups: [Group]
    public let counts: CheckCounts

    public var isEmpty: Bool { groups.isEmpty }

    /// Every id the review can offer, in display order, so "select all" needs no
    /// second traversal of the grouping.
    public var selectableIDs: [Int64] { groups.flatMap { $0.items.map(\.id) } }

    public init(groups: [Group], counts: CheckCounts) {
        self.groups = groups
        self.counts = counts
    }

    public static func build(
        from mistakes: [Mistake],
        counts: CheckCounts,
        limits: Limits = .default
    ) -> MistakeDigest {
        // `.noIssue` is what a correct sentence reports. It should never reach
        // the log at all, but a row from a hand edited file or an older build
        // would make a card with nothing on it.
        let byCategory = Dictionary(grouping: mistakes.filter { $0.category != .noIssue }, by: \.category)

        let groups = byCategory.map { category, all -> Group in
            let candidates = all
                .filter { !$0.exported }
                .sorted(by: worthStudyingFirst)
                .prefix(limits.maxItemsPerGroup)
            return Group(
                category: category,
                count: all.count,
                highSeverityCount: all.count { $0.severity == .high },
                items: Array(candidates)
            )
        }

        return MistakeDigest(
            groups: Array(
                groups
                    // A category you have already turned into cards is not a
                    // list of nothing, it is a category with nothing left to do.
                    .filter { !$0.items.isEmpty }
                    .sorted(by: mostWorthStudying)
                    .prefix(limits.maxGroups)
            ),
            counts: counts
        )
    }

    /// Frequency first, because the README's promise is "the mistakes you
    /// actually repeat" and a habit is what an Anki card is for. Seriousness
    /// breaks the tie rather than leading: one bad slip you will never make
    /// again is worth less study than nine small ones you make daily.
    ///
    /// The last two rules exist only to make the order total. Without them the
    /// list reshuffles between launches and no test can assert it.
    private static func mostWorthStudying(_ a: Group, _ b: Group) -> Bool {
        if a.count != b.count { return a.count > b.count }
        if a.highSeverityCount != b.highSeverityCount { return a.highSeverityCount > b.highSeverityCount }
        return a.category.rawValue < b.category.rawValue
    }

    /// Serious before minor, then most recent, then by id so two rows that share
    /// a second still have a fixed order.
    private static func worthStudyingFirst(_ a: Mistake, _ b: Mistake) -> Bool {
        if a.severity != b.severity { return a.severity == .high }
        if a.at != b.at { return a.at > b.at }
        return a.id > b.id
    }
}
