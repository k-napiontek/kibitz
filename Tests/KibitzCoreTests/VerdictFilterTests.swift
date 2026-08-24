import Testing
@testable import KibitzCore

@Suite("VerdictFilter")
struct VerdictFilterTests {

    private func verdict(
        _ outcome: Verdict.Outcome = .error,
        category: Category = .article,
        severity: Severity = .high
    ) -> Verdict {
        Verdict(
            outcome: outcome,
            category: category,
            severity: severity,
            corrected: "I sent you an email.",
            whyL1: "Policzalny rzeczownik w liczbie pojedynczej wymaga przedimka."
        )
    }

    @Test("a correct sentence produces no popup")
    func okIsNeverShown() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(.ok, category: .noIssue)) == .logOnly(.sentenceIsCorrect))
    }

    @Test("errors worth learning from are shown")
    func articleErrorIsShown() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .article)) == .show)
    }

    @Test("by default a missing comma never interrupts")
    func punctuationIsMutedByDefault() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .punctuation)) == .logOnly(.categoryMuted))
    }

    @Test("by default a lowercase i never interrupts")
    func capitalizationIsMutedByDefault() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .capitalization)) == .logOnly(.categoryMuted))
    }

    @Test("spelling is left to the system autocorrect")
    func spellingIsMutedByDefault() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .spelling)) == .logOnly(.categoryMuted))
    }

    @Test("the learner categories are all shown by default")
    func learnerCategoriesAreShownByDefault() {
        let filter = VerdictFilter(config: .default)
        let learnerCategories: [Category] = [
            .article, .tense, .preposition, .wordOrder, .wordChoice, .naturalness, .agreement
        ]

        for category in learnerCategories {
            #expect(filter.apply(verdict(category: category)) == .show, "\(category) should be shown")
        }
    }

    @Test("low severity findings can be muted as a group")
    func lowSeverityCanBeMuted() {
        var config = FilterConfig.default
        config.muteLowSeverity = true
        let filter = VerdictFilter(config: config)

        #expect(filter.apply(verdict(category: .article, severity: .low)) == .logOnly(.lowSeverity))
        #expect(filter.apply(verdict(category: .article, severity: .high)) == .show)
    }

    @Test("muting a category is reversible without touching the code")
    func categoryMutingIsConfigurable() {
        var config = FilterConfig.default
        config.mutedCategories.remove(.punctuation)
        let filter = VerdictFilter(config: config)

        #expect(filter.apply(verdict(category: .punctuation)) == .show)
    }
}
