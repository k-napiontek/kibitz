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

    /// Where to anchor the popup, in Accessibility (top-left origin) coordinates.
    ///
    /// Tries hardest to land under the actual text. Falling back to the mouse
    /// pointer puts the popup wherever the cursor happens to rest, which is
    /// usually nowhere near what is being corrected.
    func anchorRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1.0)
        guard let element = copy(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        let focused = element as! AXUIElement

        if let range = selectionRange(of: focused) {
            // The selected text itself, so the popup sits under what was checked.
            if range.length > 0, let rect = bounds(of: focused, range: range) {
                DiagnosticLog.write("anchor: selection bounds \(rect.debugDescription)")
                return rect
            }
            let caret = CFRange(location: max(0, range.location - 1), length: 1)
            if let rect = bounds(of: focused, range: caret), rect.height > 0 {
                DiagnosticLog.write("anchor: caret bounds \(rect.debugDescription)")
                return rect
            }
        }
        // Chrome and WebKit expose geometry through text markers rather than
        // character ranges, which is why kAXBoundsForRange returns nothing there.
        if let rect = boundsFromTextMarkers(focused) {
            DiagnosticLog.write("anchor: text marker bounds \(rect.debugDescription)")
            return rect
        }

        // Only if it is plausibly a text run. Chrome reports the whole page as
        // the focused field, and anchoring to a 900pt tall box puts the popup in
        // a screen corner, which is worse than admitting we do not know.
        if let rect = frame(of: focused), rect.height <= 160 {
            DiagnosticLog.write("anchor: field frame \(rect.debugDescription)")
            return rect
        }
        DiagnosticLog.write("anchor: NONE, falling back to mouse")
        return nil
    }

    private func bounds(of element: AXUIElement, range: CFRange) -> CGRect? {
        var query = range
        guard let axRange = AXValueCreate(.cfRange, &query) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &result
        ) == .success, let value = result else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0
        else { return nil }
        return rect
    }

    private func boundsFromTextMarkers(_ element: AXUIElement) -> CGRect? {
        guard let markerRange = copy(element, "AXSelectedTextMarkerRange") else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &result
        ) == .success, let value = result else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0
        else { return nil }
        return rect
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute),
              let sizeValue = copy(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
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
