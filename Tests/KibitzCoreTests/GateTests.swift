import Testing
@testable import KibitzCore

@Suite("Gate")
struct GateTests {

    private func input(
        sentence: String = "I have 20 years and I work here since 2020.",
        appBundleID: String = "com.tinyspeck.slackmacgap",
        secureInputActive: Bool = false,
        secureField: Bool = false,
        source: CaptureSource = .automatic
    ) -> GateInput {
        GateInput(
            sentence: sentence,
            appBundleID: appBundleID,
            isSecureInputActive: secureInputActive,
            isSecureField: secureField,
            source: source
        )
    }

    @Test("secure input is a hard stop, even for an allowlisted app")
    func secureInputIsAHardStop() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        let decision = gate.decide(input(secureInputActive: true))

        #expect(decision == .skip(.secureInputActive))
    }

    @Test("a secure text field is a hard stop")
    func secureFieldIsAHardStop() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        #expect(gate.decide(input(secureField: true)) == .skip(.secureField))
    }

    @Test("automatic capture is refused for an app that is not on the allowlist")
    func automaticCaptureRequiresAllowlist() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        let decision = gate.decide(input(appBundleID: "com.apple.Terminal", source: .automatic))

        #expect(decision == .skip(.appNotAllowed))
    }

    @Test("the hotkey works in any app, allowlist or not")
    func hotkeyBypassesAllowlist() {
        var gate = Gate(allowlist: [])

        let decision = gate.decide(input(appBundleID: "com.mitchellh.ghostty", source: .hotkey))

        #expect(decision == .check)
    }

    @Test("sentences under four words are not worth a round trip")
    func tooShortIsSkipped() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        #expect(gate.decide(input(sentence: "I am here.")) == .skip(.tooShort))
    }

    @Test("four words is long enough to check")
    func fourWordsIsLongEnough() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        #expect(gate.decide(input(sentence: "I am here now.")) == .check)
    }

    @Test("the same sentence is never checked twice")
    func repeatedSentenceIsSkipped() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])
        let first = gate.decide(input())

        let second = gate.decide(input())

        #expect(first == .check)
        #expect(second == .skip(.alreadyChecked))
    }

    @Test("dedupe ignores case and surrounding whitespace")
    func dedupeIsNormalized() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])
        _ = gate.decide(input(sentence: "I have 20 years and I work here."))

        let again = gate.decide(input(sentence: "  i HAVE 20 years   and i work here.  "))

        #expect(again == .skip(.alreadyChecked))
    }

    @Test("stays quiet when the writer switches to their own language")
    func polishIsSkipped() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        let decision = gate.decide(input(
            sentence: "Zastanawiam sie czy mozna zrobic takie narzedzie na moim komputerze."
        ))

        #expect(decision == .skip(.notEnglish))
    }

    @Test("does not correct code, URLs or file paths")
    func codeShapedTextIsSkipped() {
        var gate = Gate(allowlist: ["com.tinyspeck.slackmacgap"])

        #expect(gate.decide(input(sentence: "let decision = gate.decide(input(source: .hotkey))"))
                == .skip(.looksLikeCode))
        #expect(gate.decide(input(sentence: "See https://platform.claude.com/docs for the details."))
                == .skip(.looksLikeCode))
        #expect(gate.decide(input(sentence: "It lives in /Users/me/Documents/projects now."))
                == .skip(.looksLikeCode))
    }

    @Test("secure input outranks every other skip reason")
    func secureInputOutranksOtherReasons() {
        var gate = Gate(allowlist: [])

        let decision = gate.decide(input(
            sentence: "let x = 1",
            appBundleID: "com.apple.Terminal",
            secureInputActive: true,
            secureField: true
        ))

        #expect(decision == .skip(.secureInputActive))
    }
}
