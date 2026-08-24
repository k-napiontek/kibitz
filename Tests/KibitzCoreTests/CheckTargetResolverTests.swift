import Testing
@testable import KibitzCore

@Suite("CheckTargetResolver")
struct CheckTargetResolverTests {

    private func focused(
        value: String? = nil,
        selectedText: String? = nil,
        caretOffset: Int? = nil,
        appBundleID: String = "com.tinyspeck.slackmacgap",
        isSecureField: Bool = false
    ) -> FocusedText {
        FocusedText(
            value: value, selectedText: selectedText, caretOffset: caretOffset,
            appBundleID: appBundleID, isSecureField: isSecureField
        )
    }

    @Test("a password field is never read, whatever else is available")
    func secureFieldOutranksEverything() {
        let target = CheckTargetResolver.resolve(focused(
            value: "hunter2 is my password", selectedText: "hunter2", isSecureField: true
        ))

        #expect(target == .nothing(.secureField))
    }

    @Test("a selection is checked in preference to the sentence at the caret")
    func selectionWins() {
        let target = CheckTargetResolver.resolve(focused(
            value: "I fixed the bug. I am interested of this.",
            selectedText: "I am interested of this.",
            caretOffset: 5
        ))

        #expect(target == .selection("I am interested of this."))
    }

    @Test("a selection is trimmed, since double-clicking drags whitespace along")
    func selectionIsTrimmed() {
        let target = CheckTargetResolver.resolve(focused(selectedText: "  I am here now.  \n"))

        #expect(target == .selection("I am here now."))
    }

    @Test("a whitespace-only selection falls through instead of being checked")
    func whitespaceSelectionIsNotASelection() {
        let target = CheckTargetResolver.resolve(focused(
            value: "I have 20 years and I work here.", selectedText: "   ", caretOffset: 31
        ))

        #expect(target == .sentence("I have 20 years and I work here.", previous: nil))
    }

    @Test("with no selection, the sentence at the caret is checked")
    func sentenceAtCaret() {
        let text = "We merged the refactor. The tests was failing."

        let target = CheckTargetResolver.resolve(focused(value: text, caretOffset: text.count))

        #expect(target == .sentence("The tests was failing.", previous: "We merged the refactor."))
    }

    @Test("without a caret position the last sentence is used, not the whole field")
    func noCaretUsesLastSentence() {
        let text = "First one here. Second one here. I am interested of this."

        let target = CheckTargetResolver.resolve(focused(value: text, caretOffset: nil))

        #expect(target == .sentence("I am interested of this.", previous: "Second one here."))
    }

    @Test("an empty field has nothing to check")
    func emptyFieldIsNothing() {
        #expect(CheckTargetResolver.resolve(focused(value: "")) == .nothing(.noReadableText))
        #expect(CheckTargetResolver.resolve(focused(value: "   \n ")) == .nothing(.noReadableText))
    }

    @Test("no value and no selection means the app exposed nothing readable")
    func nothingReadable() {
        #expect(CheckTargetResolver.resolve(focused()) == .nothing(.noReadableText))
    }
}
