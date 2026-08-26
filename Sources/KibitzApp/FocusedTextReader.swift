import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KibitzCore

/// What one Accessibility traversal found: the text, and where it is on screen.
struct FocusedSnapshot {
    let text: FocusedText
    let anchor: TextAnchor
}

/// Reads whatever the focused text field is willing to expose.
///
/// Coverage varies enormously between apps: native apps expose value and caret,
/// Electron apps often expose the element but not its contents, and terminals
/// answer their whole visible screen as one value with no selection in it.
/// Everything here is best effort, and `CheckTargetResolver` decides what to do
/// with the result - including when to distrust a value it was handed.
@MainActor
struct FocusedTextReader {

    /// Held across checks, so an app is asked to expose its tree once rather
    /// than on every hotkey press.
    private let activator = AccessibilityActivator()

    /// Anything taller than this is a document, not a line of text. Chrome
    /// reports the whole page as the focused field, and anchoring to a 900 point
    /// tall box puts the popup nowhere near what was written.
    private let maxFieldHeight: CGFloat = 160

    /// Reads the text and its position in a single traversal.
    ///
    /// These used to be two separate calls, `read()` at the hotkey and
    /// `anchorRect()` after the model answered some five seconds later. They
    /// resolved the focused element independently, so clicking elsewhere during
    /// a check moved the popup to whatever was focused by then.
    func capture() async -> FocusedSnapshot {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"

        // Hard stop. Secure input means a password field is active somewhere, and
        // nothing is read at all: not the value, not even the element.
        if IsSecureEventInputEnabled() {
            return blind(bundleID: bundleID, isSecureField: true)
        }

        var candidate = focusedElement()

        // Chromium and Electron withhold their content until a client asks, and
        // an app that has nothing to say looks identical to an empty field. Ask,
        // then look again.
        if withholding(candidate), let pid = frontmostPID(), activator.activate(pid: pid) {
            DiagnosticLog.write("accessibility: asked \(bundleID) to expose its tree")
            candidate = await waitForTree()
            DiagnosticLog.write("accessibility: after asking, focused=\(candidate != nil)")
        }

        guard let focused = candidate else {
            return blind(bundleID: bundleID, isSecureField: false)
        }

        let role = copy(focused, kAXRoleAttribute) as? String
        let subrole = copy(focused, kAXSubroleAttribute) as? String
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return blind(bundleID: bundleID, isSecureField: true)
        }

        let anchor = anchor(of: focused)
        DiagnosticLog.write("anchor: source=\(anchor.source.rawValue) rect=\(anchor.rect.debugDescription)")

        let fieldValue = copy(focused, kAXValueAttribute) as? String
        let selected = copy(focused, kAXSelectedTextAttribute) as? String
        if fieldValue == nil, selected == nil {
            describeUnreadable(focused, bundleID: bundleID, role: role, subrole: subrole)
        }

        return FocusedSnapshot(
            text: FocusedText(
                value: fieldValue,
                selectedText: selected,
                caretOffset: selectionRange(of: focused)?.location,
                appBundleID: bundleID,
                isSecureField: false
            ),
            anchor: anchor
        )
    }

    /// The focused element, asking the frontmost app directly when the
    /// system-wide query comes back empty.
    ///
    /// The two disagree more often than they should: the system-wide element
    /// answers nothing for an app whose tree is not built, while the application
    /// element still answers for its own chrome.
    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1.0)
        if let value = copy(systemWide, kAXFocusedUIElementAttribute),
           let focused = element(value) {
            return focused
        }
        guard let pid = frontmostPID() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let value = copy(app, kAXFocusedUIElementAttribute) else { return nil }
        return element(value)
    }

    /// Whether this is worth asking an app about: no element at all, or one that
    /// exposes neither a value nor a selection.
    private func withholding(_ focused: AXUIElement?) -> Bool {
        guard let focused else { return true }
        return copy(focused, kAXValueAttribute) == nil
            && copy(focused, kAXSelectedTextAttribute) == nil
    }

    /// Chromium builds the tree asynchronously, so the element is not there the
    /// instant the attribute is written. Polling for it is the difference
    /// between a first hotkey press that works and one that reports an empty
    /// field. Sleeps rather than blocks, so the menu bar stays live.
    private func waitForTree() async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            let candidate = focusedElement()
            if !withholding(candidate) { return candidate }
        }
        return focusedElement()
    }

    private func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Records what an app exposes when it has no focused element at all.
    ///
    /// Chrome answers for its own toolbar while returning nothing for the page,
    /// because it builds the web content tree only once an assistive client
    /// asks for it. Whether AXManualAccessibility and AXEnhancedUserInterface
    /// are listed on the application element says whether that is what happened.
    private func describeMissingFocus(bundleID: String) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            DiagnosticLog.write("unreadable: app=\(bundleID) no frontmost process")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        DiagnosticLog.write("""
            unreadable: app=\(bundleID) no focused element \
            attributes=[\(names(of: app).joined(separator: " "))]
            """)
    }

    /// Records what an app that exposed no text does expose.
    ///
    /// "Nothing readable in that field" is the same message whether the field is
    /// empty, the app maps it to a role with no value, or it withholds text from
    /// assistive clients entirely. Attribute names separate those without
    /// writing any of what someone typed: names only, never values.
    private func describeUnreadable(
        _ element: AXUIElement, bundleID: String, role: String?, subrole: String?
    ) {
        DiagnosticLog.write("""
            unreadable: app=\(bundleID) role=\(role ?? "nil") subrole=\(subrole ?? "nil") \
            attributes=[\(names(of: element).joined(separator: " "))] \
            parameterized=[\(parameterizedNames(of: element).joined(separator: " "))]
            """)
    }

    private func names(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    private func parameterizedNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    /// Nothing readable. The anchor still has to be real, because the popup may
    /// yet be shown to explain why nothing happened.
    private func blind(bundleID: String, isSecureField: Bool) -> FocusedSnapshot {
        // Nothing is asked of Accessibility while secure input is on, not even
        // which window is frontmost. The popup is never shown for a password
        // field, so the anchor only has to exist.
        let anchor = isSecureField ? primaryScreenAnchor() : windowAnchor(of: nil)
        if !isSecureField { describeMissingFocus(bundleID: bundleID) }
        DiagnosticLog.write("anchor: source=\(anchor.source.rawValue) rect=\(anchor.rect.debugDescription)")
        return FocusedSnapshot(
            text: FocusedText(
                value: nil, selectedText: nil, caretOffset: nil,
                appBundleID: bundleID, isSecureField: isSecureField
            ),
            anchor: anchor
        )
    }

    // MARK: - Where the text is

    /// Where to anchor the popup, in Accessibility (top-left origin) coordinates.
    ///
    /// Tries hardest to land under the actual text, and always answers. The
    /// pointer is never consulted: it usually rests nowhere near what is being
    /// corrected, often on another display entirely.
    private func anchor(of focused: AXUIElement) -> TextAnchor {
        if let range = selectionRange(of: focused) {
            // The selected text itself, so the popup sits under what was checked.
            if range.length > 0, let rect = bounds(of: focused, range: range) {
                return TextAnchor(rect: rect, source: .selection)
            }
            // Some apps answer a zero-length range with the caret bar itself.
            // Others need a real character to measure, so the one before the
            // caret is tried as well.
            let carets = [
                CFRange(location: range.location, length: 0),
                CFRange(location: max(0, range.location - 1), length: 1)
            ]
            for caret in carets {
                if let rect = bounds(of: focused, range: caret) {
                    return TextAnchor(rect: rect, source: .caret)
                }
            }
        }
        // Chrome and WebKit expose geometry through text markers rather than
        // character ranges, which is why kAXBoundsForRange returns nothing there.
        if let raw = boundsFromTextMarkers(focused), let rect = usable(raw) {
            return TextAnchor(rect: rect, source: raw.width > 0 ? .textMarker : .caret)
        }
        if let rect = boundsOfCaretLine(focused) {
            return TextAnchor(rect: rect, source: .line)
        }
        if let rect = frame(of: focused), rect.height <= maxFieldHeight {
            return TextAnchor(rect: rect, source: .fieldFrame)
        }
        return windowAnchor(of: focused)
    }

    /// A caret is legitimately zero-width.
    ///
    /// Requiring a positive width is what produced "anchor: NONE, falling back
    /// to mouse" for every check without a selection in Electron and WebKit
    /// apps: a collapsed marker range has no width, but its origin and height
    /// are exactly what placing the popup needs. Only a rect with no height is
    /// genuinely useless.
    private func usable(_ rect: CGRect) -> CGRect? {
        guard rect.height > 0 else { return nil }
        guard rect.width <= 0 else { return rect }
        return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
    }

    private func bounds(of element: AXUIElement, range: CFRange) -> CGRect? {
        var query = range
        guard let axRange = AXValueCreate(.cfRange, &query) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &result
        ) == .success, let value = result, let box = axValue(value) else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(box, .cgRect, &rect) else { return nil }
        return usable(rect)
    }

    private func boundsFromTextMarkers(_ element: AXUIElement) -> CGRect? {
        guard let markerRange = copy(element, "AXSelectedTextMarkerRange") else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &result
        ) == .success, let value = result, let box = axValue(value) else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(box, .cgRect, &rect) else { return nil }
        return rect
    }

    /// The bounds of the line the caret sits on.
    ///
    /// Several apps decline kAXBoundsForRange for the selection but answer it
    /// for a whole line, and a line's bottom edge is exactly where the popup
    /// belongs.
    private func boundsOfCaretLine(_ element: AXUIElement) -> CGRect? {
        guard let line = copy(element, kAXInsertionPointLineNumberAttribute) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXRangeForLineParameterizedAttribute as CFString, line, &result
        ) == .success, let value = result, let box = axValue(value) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(box, .cfRange, &range) else { return nil }
        return bounds(of: element, range: range)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute),
              let sizeValue = copy(element, kAXSizeAttribute),
              let positionBox = axValue(positionValue),
              let sizeBox = axValue(sizeValue) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionBox, .cgPoint, &origin),
              AXValueGetValue(sizeBox, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The last resort, and deliberately not the mouse pointer.
    ///
    /// Terminals and some Electron apps expose no text geometry at all. Their
    /// window still says which display the work is on, which is the part that
    /// matters: the pointer routinely rests on another monitor entirely.
    private func windowAnchor(of focused: AXUIElement?) -> TextAnchor {
        if let focused,
           let value = copy(focused, kAXWindowAttribute),
           let window = element(value),
           let rect = frame(of: window) {
            return TextAnchor(rect: rect, source: .window)
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1.0)
            for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
                if let value = copy(app, attribute),
                   let window = element(value),
                   let rect = frame(of: window) {
                    return TextAnchor(rect: rect, source: .window)
                }
            }
        }
        // Nothing is exposed at all. The primary display is still a real place,
        // and it is where an app that answers nothing is most likely to be.
        return primaryScreenAnchor()
    }

    /// The primary display, in the Accessibility coordinates it defines: its own
    /// top left corner is the origin they are all measured from.
    private func primaryScreenAnchor() -> TextAnchor {
        TextAnchor(
            rect: CGRect(origin: .zero, size: NSScreen.screens.first?.frame.size ?? .zero),
            source: .window
        )
    }

    // MARK: - Accessibility plumbing

    private func selectionRange(of element: AXUIElement) -> CFRange? {
        guard let value = copy(element, kAXSelectedTextRangeAttribute),
              let box = axValue(value) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(box, .cfRange, &range) else { return nil }
        return range
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    /// Checked casts rather than `as!`, because these values come from whatever
    /// app happens to be focused. One that answers an attribute with the wrong
    /// type would otherwise take the whole menu bar agent down with it.
    private func axValue(_ value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private func element(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
