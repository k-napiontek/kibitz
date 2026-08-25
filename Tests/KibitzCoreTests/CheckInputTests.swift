import Testing
@testable import KibitzCore

@Suite("CheckInput")
struct CheckInputTests {

    @Test("sends the literal word NONE when there is no preceding sentence")
    func formatsWithoutContext() {
        let formatted = CheckInput.format(sentence: "I have 20 years.", previous: nil)

        #expect(formatted == "NONE\n---\nI have 20 years.")
    }

    @Test("passes the preceding sentence as context above the separator")
    func formatsWithContext() {
        let formatted = CheckInput.format(
            sentence: "The tests was failing.", previous: "We merged the refactor."
        )

        #expect(formatted == "We merged the refactor.\n---\nThe tests was failing.")
    }

    @Test("whitespace-only context is no context, so the cached prefix stays stable")
    func treatsBlankContextAsNone() {
        #expect(CheckInput.format(sentence: "Let's ship it.", previous: "   \n ")
            == "NONE\n---\nLet's ship it.")
    }

    @Test("both backends format the input identically, or they are not comparable")
    func isTheOnlyFormatter() {
        let sentence = "The tests was failing."
        let context = "We merged the refactor."
        let provider = ClaudeCodeProvider(systemPrompt: "PROMPT")

        let arguments = provider.arguments(for: sentence, previous: context)

        #expect(arguments.contains(CheckInput.format(sentence: sentence, previous: context)))
    }
}
