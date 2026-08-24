import Testing
@testable import KibitzCore

@Suite("SentenceDiff")
struct SentenceDiffTests {

    private func changed(_ original: String, _ corrected: String) -> [String] {
        SentenceDiff.spans(original: original, corrected: corrected)
            .filter(\.isChanged).map(\.text)
    }

    private func rendered(_ original: String, _ corrected: String) -> String {
        SentenceDiff.spans(original: original, corrected: corrected).map(\.text).joined()
    }

    @Test("the spans always reassemble into the corrected sentence")
    func spansReassemble() {
        let corrected = "I am 20 years old and I have worked here since 2020."

        #expect(rendered("I have 20 years and I work here since 2020.", corrected) == corrected)
    }

    @Test("an identical sentence has nothing highlighted")
    func identicalHasNoChanges() {
        #expect(changed("It works on my machine.", "It works on my machine.").isEmpty)
    }

    @Test("an inserted article is the only thing highlighted")
    func insertedArticleIsHighlighted() {
        #expect(changed("I sent you email.", "I sent you an email.") == ["an"])
    }

    @Test("words the writer got right are not highlighted")
    func untouchedWordsStayQuiet() {
        let marks = changed("I have 20 years.", "I am 20 years old.")

        #expect(marks.contains("am"))
        #expect(marks.contains("old."))
        #expect(!marks.contains("I"))
        #expect(!marks.contains("20"))
    }

    @Test("a completely rewritten sentence highlights everything")
    func fullRewriteHighlightsAll() {
        let spans = SentenceDiff.spans(original: "Zupelnie inne zdanie.", corrected: "Totally different words.")

        #expect(spans.allSatisfy { $0.isChanged || $0.text.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test("an empty original marks the whole correction as new")
    func emptyOriginalIsAllNew() {
        let marks = changed("", "I am here now.")

        #expect(marks.contains("I"))
        #expect(marks.contains("now."))
    }
}
