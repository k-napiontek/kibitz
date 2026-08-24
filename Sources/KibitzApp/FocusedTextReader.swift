import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KibitzCore

/// Reads whatever the focused text field is willing to expose.
///
/// Coverage varies enormously between apps: native apps expose value and caret,
/// Electron apps often expose the element but not its contents, terminals expose
/// nothing at all. Everything here is best effort, and `CheckTargetResolver`
/// decides what to do with the result.
struct FocusedTextReader {

    func read() -> FocusedText {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"

        // Hard stop. Secure input means a password field is active somewhere, and
        // nothing is read at all: not the value, not even the element.
        if IsSecureEventInputEnabled() {
            return FocusedText(
                value: nil, selectedText: nil, caretOffset: nil,
                appBundleID: bundleID, isSecureField: true
            )
        }

        nudgeElectron(bundleID: bundleID)

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1.0)

        guard let element = copy(systemWide, kAXFocusedUIElementAttribute) else {
            return FocusedText(
                value: nil, selectedText: nil, caretOffset: nil,
                appBundleID: bundleID, isSecureField: false
            )
        }
        let focused = element as! AXUIElement

        let role = copy(focused, kAXRoleAttribute) as? String
        let subrole = copy(focused, kAXSubroleAttribute) as? String
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return FocusedText(
                value: nil, selectedText: nil, caretOffset: nil,
                appBundleID: bundleID, isSecureField: true
            )
        }

        return FocusedText(
            value: copy(focused, kAXValueAttribute) as? String,
            selectedText: copy(focused, kAXSelectedTextAttribute) as? String,
            caretOffset: selectionRange(of: focused)?.location,
            appBundleID: bundleID,
            isSecureField: false
        )
    }

    /// Where to put the popup. Falls back to the mouse when the app cannot say.
    func caretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1.0)
        guard let element = copy(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        let focused = element as! AXUIElement
        guard let range = selectionRange(of: focused) else { return nil }

        var query = CFRange(location: max(0, range.location - 1), length: 1)
        guard let axRange = AXValueCreate(.cfRange, &query) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &result
        ) == .success, let value = result else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Electron apps expose nothing until an assistive client asks them to.
    private func nudgeElectron(bundleID: String) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func selectionRange(of element: AXUIElement) -> CFRange? {
        guard let value = copy(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
