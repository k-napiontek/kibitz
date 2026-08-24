import Testing
@testable import KibitzCore

@Suite("PromptTemplate")
struct PromptTemplateTests {

    @Test("renders the learner's own language into the prompt")
    func rendersNativeLanguageName() {
        let template = PromptTemplate(raw: "Explain in {{L1_NAME}}, one line.")

        #expect(template.render(nativeLanguage: .polish) == "Explain in Polish, one line.")
    }

    @Test("works for a learner whose first language is not Polish")
    func rendersAnyLanguage() {
        let template = PromptTemplate(raw: "Explain in {{L1_NAME}}.")
        let spanish = NativeLanguage(code: "es", englishName: "Spanish")

        #expect(template.render(nativeLanguage: spanish) == "Explain in Spanish.")
    }

    @Test("substitutes every occurrence, not just the first")
    func rendersRepeatedPlaceholders() {
        let template = PromptTemplate(raw: "{{L1_NAME}} and {{L1_NAME}}")

        #expect(template.render(nativeLanguage: .polish) == "Polish and Polish")
    }

    @Test("the shipped prompt actually carries the placeholder")
    func bundledPromptIsParameterised() throws {
        let template = try BundledPrompt.systemPromptTemplate()

        #expect(template.raw.contains("{{L1_NAME}}"))
    }

    @Test("the rendered prompt names no language other than the learner's own")
    func renderedPromptHasNoLeftoverPlaceholders() throws {
        let rendered = try BundledPrompt.systemPromptTemplate().render(nativeLanguage: .polish)

        #expect(!rendered.contains("{{"))
        #expect(rendered.contains("Polish"))
    }

    @Test("Polish is the default until another language is configured")
    func polishIsTheDefault() {
        #expect(NativeLanguage.polish.code == "pl")
        #expect(NativeLanguage.polish.englishName == "Polish")
    }
}

@Suite("Language profiles")
struct LanguageProfileTests {

    @Test("renders the interference profile into the prompt")
    func rendersProfile() {
        let template = PromptTemplate(raw: "Rules:\n{{L1_PROFILE}}\nEnd.")

        let rendered = template.render(nativeLanguage: .polish, profile: "PROFILE BODY")

        #expect(rendered == "Rules:\nPROFILE BODY\nEnd.")
    }

    @Test("the shipped prompt delegates the language-specific part to a profile")
    func bundledPromptHasProfileHole() throws {
        let template = try BundledPrompt.systemPromptTemplate()

        #expect(template.raw.contains("{{L1_PROFILE}}"))
    }

    @Test("Polish ships with a profile covering the mistakes Polish speakers make")
    func polishProfileExists() throws {
        let profile = try BundledPrompt.profile(for: .polish)

        #expect(profile.contains("article"))
        #expect(profile.contains("I have 20 years"))
    }

    @Test("a language with no profile fails loudly rather than coaching badly")
    func missingProfileThrows() {
        let klingon = NativeLanguage(code: "tlh", englishName: "Klingon")

        #expect(throws: PromptError.self) {
            try BundledPrompt.profile(for: klingon)
        }
    }

    @Test("a fully rendered prompt has no placeholders left in it")
    func fullyRenderedPromptIsComplete() throws {
        let template = try BundledPrompt.systemPromptTemplate()

        let rendered = template.render(
            nativeLanguage: .polish,
            profile: try BundledPrompt.profile(for: .polish)
        )

        #expect(!rendered.contains("{{"))
        #expect(!rendered.contains("}}"))
        #expect(rendered.contains("Polish"))
        #expect(rendered.contains("I have 20 years"))
    }

    @Test("every shipped profile is listed as an available language")
    func availableLanguagesIncludesPolish() {
        #expect(BundledPrompt.availableLanguages.contains { $0.code == "pl" })
    }
}
