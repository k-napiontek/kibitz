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

    private let mechanical: [Category] = [.spelling, .punctuation, .capitalization]

    @Test("a correct sentence produces no popup, however it was checked")
    func okIsNeverShown() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(.ok, category: .noIssue), source: .hotkey) == .logOnly(.sentenceIsCorrect))
        #expect(filter.apply(verdict(.ok, category: .noIssue), source: .automatic) == .logOnly(.sentenceIsCorrect))
    }

    @Test("errors worth learning from are shown")
    func articleErrorIsShown() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .article), source: .hotkey) == .show)
        #expect(filter.apply(verdict(category: .article), source: .automatic) == .show)
    }

    @Test("by default a missing comma never interrupts typing")
    func punctuationIsMutedWhileTyping() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .punctuation), source: .automatic) == .logOnly(.categoryMuted))
    }

    @Test("by default a lowercase i never interrupts typing")
    func capitalizationIsMutedWhileTyping() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .capitalization), source: .automatic) == .logOnly(.categoryMuted))
    }

    @Test("spelling is left to the system autocorrect while typing")
    func spellingIsMutedWhileTyping() {
        let filter = VerdictFilter(config: .default)

        #expect(filter.apply(verdict(category: .spelling), source: .automatic) == .logOnly(.categoryMuted))
    }

    // The bug this suite exists to keep out: a hotkey press on
    // "explain this is scc in the openshift" came back labelled capitalization,
    // and the mute threw away a correction that also fixed an article. Muting is
    // about not interrupting someone mid-sentence, and a press is not an
    // interruption. Whatever the label says, an answer that was asked for is owed.
    @Test("a muted category still answers a hotkey press")
    func mutedCategoriesStillAnswerAHotkeyPress() {
        let filter = VerdictFilter(config: .default)

        for category in mechanical {
            #expect(
                filter.apply(verdict(category: category), source: .hotkey) == .show,
                "\(category) was asked for, so it owes an answer"
            )
        }
    }

    @Test("the learner categories are all shown by default")
    func learnerCategoriesAreShownByDefault() {
        let filter = VerdictFilter(config: .default)
        let learnerCategories: [Category] = [
            .article, .tense, .preposition, .wordOrder, .wordChoice, .naturalness, .agreement
        ]

        for category in learnerCategories {
            #expect(
                filter.apply(verdict(category: category), source: .automatic) == .show,
                "\(category) should be shown"
            )
        }
    }

    @Test("low severity findings can be muted as a group while typing")
    func lowSeverityCanBeMuted() {
        var config = FilterConfig.default
        config.muteLowSeverity = true
        let filter = VerdictFilter(config: config)

        #expect(filter.apply(verdict(category: .article, severity: .low), source: .automatic) == .logOnly(.lowSeverity))
        #expect(filter.apply(verdict(category: .article, severity: .high), source: .automatic) == .show)
    }

    @Test("a low severity finding still answers a hotkey press")
    func lowSeverityStillAnswersAHotkeyPress() {
        var config = FilterConfig.default
        config.muteLowSeverity = true
        let filter = VerdictFilter(config: config)

        #expect(filter.apply(verdict(category: .article, severity: .low), source: .hotkey) == .show)
    }

    @Test("muting a category is reversible without touching the code")
    func categoryMutingIsConfigurable() {
        var config = FilterConfig.default
        config.mutedCategories.remove(.punctuation)
        let filter = VerdictFilter(config: config)

        #expect(filter.apply(verdict(category: .punctuation), source: .automatic) == .show)
    }
}
