import Foundation
import Testing
@testable import KibitzCore

@Suite("AnkiExport")
struct AnkiExportTests {

    private func mistake(
        original: String = "I work here since 2020.",
        corrected: String = "I have worked here since 2020.",
        whyL1: String = "'since 2020' wymaga present perfect.",
        category: KibitzCore.Category = .tense,
        severity: Severity = .high
    ) -> Mistake {
        Mistake(
            id: 1,
            at: Date(timeIntervalSince1970: 1_756_108_800),
            category: category,
            severity: severity,
            original: original,
            corrected: corrected,
            whyL1: whyL1,
            app: nil,
            exported: false
        )
    }

    private func rows(_ mistakes: [Mistake]) -> [String] {
        AnkiExport.tsv(for: mistakes)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
    }

    private func fields(_ mistake: Mistake) -> [String] {
        let row = try! #require(rows([mistake]).first)
        return row.components(separatedBy: "\t")
    }

    @Test("the file opens with the three header lines anki needs")
    func writesTheImportHeader() {
        let text = AnkiExport.tsv(for: [mistake()])
        let lines = text.split(separator: "\n").map(String.init)

        #expect(lines[0] == "#separator:tab")
        #expect(lines[1] == "#html:true")
        #expect(lines[2] == "#tags column:3")
    }

    @Test("the front is the sentence as it was written")
    func frontIsWhatYouTyped() {
        #expect(fields(mistake())[0] == "I work here since 2020.")
    }

    @Test("the back marks the words that changed and nothing else")
    func backBoldsOnlyTheDiff() {
        let back = fields(mistake())[1]

        // Two runs rather than one, because SentenceDiff emits the space between
        // two words as its own unchanged span. It renders identically in Anki and
        // in the popup, so do not "fix" the diff to merge across the space: that
        // breaks SentenceDiffTests for a difference nobody can see.
        #expect(back.hasPrefix("I <b>have</b> <b>worked</b> here since 2020."))
        #expect(back.contains("<b>I</b>") == false)
    }

    @Test("the explanation follows the correction after a line break")
    func backCarriesTheExplanation() {
        let back = fields(mistake())[1]

        #expect(back.hasSuffix("<br>'since 2020' wymaga present perfect."))
    }

    @Test("every card has exactly three tab separated fields")
    func rowsHaveExactlyThreeFields() {
        let awkward = mistake(original: "a\tb\tc", corrected: "a\tb\td", whyL1: "why\there")

        #expect(fields(awkward).count == 3)
    }

    @Test("a tab inside a sentence never becomes a fourth field")
    func tabsAreNeutralised() {
        let parts = fields(mistake(original: "I work\there since 2020."))

        #expect(parts.count == 3)
        #expect(parts[0] == "I work here since 2020.")
    }

    @Test("a newline inside a sentence never becomes a second card")
    func newlinesNeverSplitTheRow() {
        let awkward = mistake(original: "I work here\nsince 2020.", whyL1: "linia\ndruga")

        #expect(rows([awkward]).count == 1)
        #expect(fields(awkward)[0].contains("\n") == false)
    }

    @Test("a sentence starting with a quote is not swallowed by the csv reader")
    func leadingQuotesAreEscaped() {
        let parts = fields(mistake(original: "\"I work here\", he said."))

        #expect(parts[0].hasPrefix("&quot;"))
        #expect(parts[0].contains("\"") == false)
    }

    @Test("angle brackets show as text, not as markup")
    func markupInTheSentenceIsEscaped() {
        let parts = fields(mistake(original: "Use <b> for bold."))

        #expect(parts[0] == "Use &lt;b&gt; for bold.")
    }

    @Test("an ampersand is escaped once, not twice")
    func ampersandsAreEscapedOnce() {
        // & has to be replaced before < and >, or the ampersand this rule just
        // introduced gets escaped again and the card shows &amp;lt;.
        let parts = fields(mistake(original: "Tom & Jerry <here>"))

        #expect(parts[0] == "Tom &amp; Jerry &lt;here&gt;")
    }

    @Test("escaping runs before the bold tags, or the card shows them literally")
    func boldSurvivesEscaping() {
        let back = fields(mistake(original: "I need <thing>.", corrected: "I need a <thing>."))[1]

        #expect(back.contains("<b>") == true)
        #expect(back.contains("&lt;thing&gt;") == true)
        #expect(back.contains("&lt;b&gt;") == false)
    }

    @Test("the tags name kibitz, the category and the severity")
    func tagsCarryCategoryAndSeverity() {
        #expect(fields(mistake(category: .wordOrder, severity: .low))[2] == "kibitz word-order low")
    }

    @Test("no category raw value contains a space, or anki would split the tag")
    func categoryNamesAreSafeAsTags() {
        for category in KibitzCore.Category.allCases {
            #expect(category.rawValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil)
        }
    }

    @Test("polish text survives, since that is half of every card")
    func nonAsciiSurvives() {
        let parts = fields(mistake(whyL1: "Zażółć gęślą jaźń."))

        #expect(parts[1].hasSuffix("Zażółć gęślą jaźń."))
    }

    @Test("no mistakes produces a header and nothing else")
    func emptyExportIsJustTheHeader() {
        #expect(rows([]).isEmpty)
        #expect(AnkiExport.tsv(for: []).hasPrefix("#separator:tab"))
    }

    @Test("the filename carries the date, so last week's file is not overwritten")
    func filenameIsDated() {
        let name = AnkiExport.filename(for: Date(timeIntervalSince1970: 1_756_108_800))

        #expect(name == "kibitz-2025-08-25.tsv")
    }
}
