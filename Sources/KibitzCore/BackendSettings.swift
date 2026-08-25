import Foundation

/// Which backend judges sentences.
///
/// An explicit choice rather than "use the API key if one exists", so that
/// having a key on the machine never silently changes where the sentences go.
public enum Backend: String, CaseIterable, Sendable {
    case subscription
    case deepseek

    public var menuTitle: String {
        switch self {
        case .subscription: "Claude subscription"
        case .deepseek: "DeepSeek API"
        }
    }
}

/// The backend choice, persisted.
///
/// Reads fall back to the subscription on anything unrecognised, so a hand
/// edited or downgraded preference leaves the app working rather than trapping.
public struct BackendSettings {
    public static let backendKey = "backend"
    public static let modelKey = "deepseek.model"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var backend: Backend {
        get { Backend(rawValue: defaults.string(forKey: Self.backendKey) ?? "") ?? .subscription }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.backendKey) }
    }

    public var deepSeekModel: DeepSeekModel {
        get { DeepSeekModel(rawValue: defaults.string(forKey: Self.modelKey) ?? "") ?? .flash }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modelKey) }
    }
}
