import Foundation

public enum ProviderResolutionError: Error, Equatable {
    /// The DeepSeek backend is selected but no key is stored. Recoverable, and
    /// the app says how.
    case noAPIKey
}

/// Builds the provider the settings ask for.
///
/// One implementation shared by the app and both command line harnesses, so
/// `kibitz-check` and `kibitz-corpus` always exercise the backend the app is
/// actually configured to use.
public enum ProviderResolver {

    public static func make(
        settings: BackendSettings = BackendSettings(),
        backend: Backend? = nil,
        model: DeepSeekModel? = nil,
        language: NativeLanguage = .polish,
        keys: APIKeyStore = APIKeyStore()
    ) throws -> any ModelProvider {
        let prompt = try BundledPrompt.renderedSystemPrompt(for: language)

        switch backend ?? settings.backend {
        case .subscription:
            return ClaudeCodeProvider(systemPrompt: prompt)
        case .deepseek:
            guard let key = try keys.read(), !key.isEmpty else {
                throw ProviderResolutionError.noAPIKey
            }
            return DeepSeekProvider(
                apiKey: key,
                systemPrompt: prompt,
                model: model ?? settings.deepSeekModel
            )
        }
    }
}
