import ServiceManagement

/// Puts kibitz in the login items, or takes it out.
///
/// `SMAppService.mainApp` rather than a hand written LaunchAgent plist: it is
/// the API macOS 26 wants, and it gives the person a switch in System Settings >
/// General > Login Items that they can find without knowing this app exists.
///
/// Verified to work from a Homebrew prefix - `register()` succeeds and reports
/// `.enabled` from `/opt/homebrew/opt/kibitz`, with only an ad-hoc signature -
/// so kibitz does not need to live in /Applications to start at login.
enum LaunchAtLogin {

    /// Read from the system every time, never cached. Someone can turn this off
    /// in System Settings while the app is running, and a remembered answer
    /// would leave the menu showing a checkmark for something that is off.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// For the diagnostics log. A login item that quietly stopped working after
    /// an upgrade is invisible otherwise: the app simply never appears one
    /// morning, and nothing anywhere says why.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
