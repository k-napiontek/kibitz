import Foundation

/// Whether kibitz has already put itself into the login items.
///
/// The enabled state itself is deliberately not stored here: that lives in the
/// system, and `SMAppService.status` is the only thing that can be trusted to
/// answer it, because someone can turn the login item off in System Settings
/// without the app ever running. A remembered copy would make the menu lie.
///
/// What is stored is one bit: whether registration has been attempted at all.
/// Without it, "start at login" would switch itself back on every launch and
/// the toggle would be decorative.
///
/// Same shape as `BackendSettings` and `ReviewSettings`: injected defaults, a
/// stable key, and a read that falls back rather than trapping.
public struct StartupSettings {

    public static let didRegisterKey = "startup.didRegister"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var didAttemptRegistration: Bool {
        // `object(forKey:)` rather than `bool(forKey:)`, because the latter
        // coerces a hand edited string into a value and hides the garbage.
        get { defaults.object(forKey: Self.didRegisterKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.didRegisterKey) }
    }

    /// Register on the first launch only, and never against a login item that
    /// is already on.
    public func shouldRegisterAtLaunch(isEnabled: Bool) -> Bool {
        !didAttemptRegistration && !isEnabled
    }
}
