import ApplicationServices
import Foundation

/// Asks an app to build the accessibility tree it is withholding.
///
/// Chromium and Electron do not expose their content to Accessibility until a
/// client signals that it needs it, for performance reasons. Until then a web
/// page looks exactly like an empty field, which is why the hotkey did nothing
/// on chatgpt.com or on Slack in a browser tab.
///
/// The nudge is spent lazily, only on an app that has already failed a read.
/// Turning this on costs the target app memory and CPU for as long as it runs,
/// and an app that exposes its text normally should never pay it.
@MainActor
public final class AccessibilityActivator {

    /// One attribute per family, because an app cannot be asked which it is.
    ///
    /// `AXManualAccessibility` is Electron's own invention. Chromium and Firefox
    /// watch `AXEnhancedUserInterface`, the attribute VoiceOver sets - which is
    /// why setting only the first one was a no-op on Chrome.
    public static let attributes = ["AXManualAccessibility", "AXEnhancedUserInterface"]

    private var activated: Set<pid_t> = []
    private let apply: @MainActor (pid_t, String) -> Void

    public init(
        apply: @escaping @MainActor (pid_t, String) -> Void = AccessibilityActivator.set
    ) {
        self.apply = apply
    }

    public func hasActivated(pid: pid_t) -> Bool { activated.contains(pid) }

    /// Returns whether this call actually asked, so the caller knows whether
    /// there is any point waiting for a tree to appear.
    @discardableResult
    public func activate(pid: pid_t) -> Bool {
        guard !activated.contains(pid) else { return false }
        activated.insert(pid)
        for attribute in Self.attributes { apply(pid, attribute) }
        return true
    }

    /// Written to the application element, never to a window.
    ///
    /// `AXEnhancedUserInterface` set on an `AXWindow` is what breaks window
    /// positioning for window managers like Magnet. On the application element
    /// it enables the tree without that side effect.
    public static func set(pid: pid_t, attribute: String) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue)
    }
}
