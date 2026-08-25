import Foundation
import Testing
@testable import KibitzCore

@Suite("MistakeDigest")
struct MistakeDigestTests {

    private let noon = Date(timeIntervalSince1970: 1_756_108_800)

    private func mistake(
        _ id: Int64,
        _ category: KibitzCore.Category,
        severity: Severity = .high,
        daysAgo: Double = 1,
        exported: Bool = false
    ) -> Mistake {
        Mistake(
            id: id,
            at: noon.addingTimeInterval(-daysAgo * 24 * 3600),
            category: category,
            severity: severity,
            original: "sentence \(id)",
            corrected: "corrected \(id)",
            whyL1: "wyjasnienie \(id)",
            app: nil,
            exported: exported
        )
    }

    private func digest(_ mistakes: [Mistake], limits: MistakeDigest.Limits = .default) -> MistakeDigest {
        MistakeDigest.build(
            from: mistakes,
            counts: CheckCounts(checked: 100, withMistake: mistakes.count),
            limits: limits
        )
    }

    @Test("the category you repeat most comes first")
    func frequencyLeads() {
        let result = digest([
            mistake(1, .tense), mistake(2, .article), mistake(3, .article), mistake(4, .article)
        ])

        #expect(result.groups.map(\.category) == [.article, .tense])
        #expect(result.groups.first?.count == 3)
    }

    @Test("a tie on count is broken by the more serious category")
    func severityBreaksTheTie() {
        let result = digest([
            mistake(1, .tense, severity: .low), mistake(2, .tense, severity: .low),
            mistake(3, .article, severity: .high), mistake(4, .article, severity: .low)
        ])

        #expect(result.groups.map(\.category) == [.article, .tense])
    }

    @Test("the order is total, so the list does not reshuffle between launches")
    func orderingIsDeterministic() {
        // Same count, same severity mix, same day: only a final tiebreak can
        // separate these, and without one the list moves around on every launch.
        let result = digest([mistake(1, .tense, severity: .low), mistake(2, .article, severity: .low)])

        #expect(result.groups.map(\.category) == [.article, .tense])
    }

    @Test("inside a category the serious mistakes come first")
    func itemsLeadWithSeverity() {
        let result = digest([
            mistake(1, .article, severity: .low, daysAgo: 1),
            mistake(2, .article, severity: .high, daysAgo: 5)
        ])

        #expect(result.groups.first?.items.map(\.id) == [2, 1])
    }

    @Test("equal severity falls back to the most recent")
    func itemsFallBackToRecency() {
        let result = digest([
            mistake(1, .article, daysAgo: 5),
            mistake(2, .article, daysAgo: 1)
        ])

        #expect(result.groups.first?.items.map(\.id) == [2, 1])
    }

    @Test("a correct sentence never becomes a group, there is nothing to learn")
    func dropsTheNoneCategory() {
        let result = digest([mistake(1, .noIssue), mistake(2, .article)])

        #expect(result.groups.map(\.category) == [.article])
    }

    @Test("a mistake already exported is not offered as a card twice")
    func exportedRowsAreNotOfferedAgain() {
        let result = digest([
            mistake(1, .article, exported: true),
            mistake(2, .article, exported: false)
        ])

        #expect(result.groups.first?.items.map(\.id) == [2])
    }

    @Test("a mistake already exported still counts towards its category")
    func exportedRowsStillCount() {
        // The count answers "what do you keep getting wrong", which is true
        // whether or not you have made the card yet.
        let result = digest([
            mistake(1, .article, exported: true),
            mistake(2, .article, exported: true),
            mistake(3, .article, exported: false),
            mistake(4, .tense, exported: false), mistake(5, .tense, exported: false)
        ])

        #expect(result.groups.map(\.category) == [.article, .tense])
        #expect(result.groups.first?.count == 3)
    }

    @Test("a category whose mistakes are all already cards drops off the list")
    func fullyExportedCategoriesDisappear() {
        let result = digest([
            mistake(1, .article, exported: true), mistake(2, .article, exported: true),
            mistake(3, .tense, exported: false)
        ])

        #expect(result.groups.map(\.category) == [.tense])
    }

    @Test("the list is capped, because a list you can finish gets finished")
    func respectsTheLimits() {
        let many = (1...12).map { mistake(Int64($0), .article, daysAgo: Double($0)) }
        let spread: [Mistake] = [.article, .tense, .preposition, .agreement, .spelling, .naturalness]
            .enumerated()
            .map { mistake(Int64(100 + $0.offset), $0.element) }

        let capped = digest(many + spread, limits: MistakeDigest.Limits(maxGroups: 3, maxItemsPerGroup: 5))

        #expect(capped.groups.count == 3)
        #expect(capped.groups.first?.items.count == 5)
        // The cap hides rows, it must not lie about how often it happened.
        #expect(capped.groups.first?.count == 13)
    }

    @Test("a week with nothing wrong produces an empty digest, not a crash")
    func emptyWeekIsEmpty() {
        let result = MistakeDigest.build(
            from: [], counts: CheckCounts(checked: 41, withMistake: 0), limits: .default
        )

        #expect(result.groups.isEmpty)
        #expect(result.isEmpty)
        #expect(result.counts.checked == 41)
        #expect(result.selectableIDs.isEmpty)
    }

    @Test("every card the review can offer is reachable as one flat selection")
    func exposesEverySelectableID() {
        let result = digest([mistake(1, .article), mistake(2, .tense), mistake(3, .article, exported: true)])

        #expect(result.selectableIDs == [1, 2])
    }
}
