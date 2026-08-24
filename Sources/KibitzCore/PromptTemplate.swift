import Foundation

/// The learner's first language, in the second-language-acquisition sense.
/// `englishName` is what gets written into the prompt, because the model
/// resolves an English language name more reliably than a code.
public struct NativeLanguage: Sendable, Equatable, Codable {
    public let code: String
    public let englishName: String

    public init(code: String, englishName: String) {
        self.code = code
        self.englishName = englishName
    }

    public static let polish = NativeLanguage(code: "pl", englishName: "Polish")
}

public enum PromptError: Error, Equatable {
    case bundledPromptMissing
    /// No interference profile ships for this language yet. Failing here is
    /// deliberate: coaching without a profile produces bland, generic advice.
    case noProfileFor(languageCode: String)
}

/// The coaching prompt with the learner's language left as a hole.
///
/// One template serves every backend, so switching providers cannot silently
/// change how the tool coaches.
public struct PromptTemplate: Sendable, Equatable {
    public static let languagePlaceholder = "{{L1_NAME}}"
    public static let profilePlaceholder = "{{L1_PROFILE}}"

    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public func render(nativeLanguage: NativeLanguage, profile: String = "") -> String {
        raw
            .replacingOccurrences(
                of: Self.languagePlaceholder,
                with: nativeLanguage.englishName
            )
            .replacingOccurrences(
                of: Self.profilePlaceholder,
                with: profile
            )
    }
}

public enum BundledPrompt {
    public static func systemPromptTemplate() throws -> PromptTemplate {
        guard let url = Bundle.module.url(
            forResource: "Resources/system-prompt",
            withExtension: "md"
        ) else {
            throw PromptError.bundledPromptMissing
        }
        return PromptTemplate(raw: try String(contentsOf: url, encoding: .utf8))
    }

    /// The interference patterns for one first language. Adding a language is
    /// a single new file under `Resources/profiles`.
    public static func profile(for language: NativeLanguage) throws -> String {
        guard let url = Bundle.module.url(
            forResource: "Resources/profiles/\(language.code)",
            withExtension: "md"
        ) else {
            throw PromptError.noProfileFor(languageCode: language.code)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static let availableLanguages: [NativeLanguage] = [.polish]

    /// The prompt as a backend should receive it: language and profile filled in.
    public static func renderedSystemPrompt(for language: NativeLanguage) throws -> String {
        try systemPromptTemplate().render(
            nativeLanguage: language,
            profile: profile(for: language)
        )
    }
}
