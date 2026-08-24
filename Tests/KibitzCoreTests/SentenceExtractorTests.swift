import Testing
@testable import KibitzCore

@Suite("SentenceExtractor")
struct SentenceExtractorTests {

    @Test("splits ordinary prose into sentences")
    func splitsProse() {
        let text = "I fixed the bug. The tests pass now."

        #expect(SentenceExtractor.sentences(in: text) == ["I fixed the bug.", "The tests pass now."])
    }

    @Test("does not split on an abbreviation")
    func keepsAbbreviationsWhole() {
        let text = "I asked Dr. Nowak about it yesterday."

        #expect(SentenceExtractor.sentences(in: text).count == 1)
    }

    @Test("does not split on a decimal number")
    func keepsDecimalsWhole() {
        let text = "The migration moved 3.5 million rows without failing."

        #expect(SentenceExtractor.sentences(in: text).count == 1)
    }

    @Test("handles question and exclamation marks as boundaries")
    func splitsOnOtherTerminators() {
        let text = "Did it deploy? It did! Finally."

        #expect(SentenceExtractor.sentences(in: text).count == 3)
    }

    @Test("extracts the sentence the caret sits in")
    func extractsSentenceAtCaret() {
        let text = "I fixed the bug. The tests pass now."

        let extracted = SentenceExtractor.extract(from: text, caretOffset: text.count)

        #expect(extracted?.sentence == "The tests pass now.")
    }

    @Test("supplies the preceding sentence as context")
    func suppliesPreviousSentence() {
        let text = "We merged the refactor. The tests was failing."

        let extracted = SentenceExtractor.extract(from: text, caretOffset: text.count)

        #expect(extracted?.sentence == "The tests was failing.")
        #expect(extracted?.previous == "We merged the refactor.")
    }

    @Test("the first sentence has no preceding context")
    func firstSentenceHasNoPrevious() {
        let extracted = SentenceExtractor.extract(from: "I fixed the bug.", caretOffset: 16)

        #expect(extracted?.sentence == "I fixed the bug.")
        #expect(extracted?.previous == nil)
    }

    @Test("empty text yields nothing to check")
    func emptyTextYieldsNil() {
        #expect(SentenceExtractor.extract(from: "", caretOffset: 0) == nil)
        #expect(SentenceExtractor.extract(from: "   \n  ", caretOffset: 3) == nil)
    }

    @Test("a caret in the middle picks that sentence, not the last one")
    func caretInMiddlePicksItsOwnSentence() {
        let text = "First one here. Second one here. Third one here."
        let caret = text.distance(
            from: text.startIndex,
            to: text.range(of: "Second one here.")!.upperBound
        )

        let extracted = SentenceExtractor.extract(from: text, caretOffset: caret)

        #expect(extracted?.sentence == "Second one here.")
        #expect(extracted?.previous == "First one here.")
    }

    @Test("a caret past the end of the text does not crash")
    func caretBeyondEndIsClamped() {
        let text = "I fixed the bug."

        #expect(SentenceExtractor.extract(from: text, caretOffset: 9_999)?.sentence == "I fixed the bug.")
    }
}
