import AppKit
import ApplicationServices
import KibitzCore

/// Puts an accepted correction back into the field it came from.
///
/// Tries Accessibility first because it is precise and invisible. Falls back to
/// a paste, which always borrows the clipboard through `PasteboardGuard` so the
/// person gets their own clipboard back.
struct Corrector {

    enum Outcome { case applied, failed }

    func apply(correction: String, replacing original: String, target: CheckTarget) -> Outcome {
        guard let focused = focusedElement() else { return .failed }

        switch target {
        case .selection:
            if set(focused, kAXSelectedTextAttribute, to: correction) { return .applied }
        case .sentence:
            if replaceInValue(focused, original: original, with: correction) { return .applied }
        case .nothing:
            return .failed
        }
        return paste(correction)
    }

    /// Rewrites just the sentence inside the field's full value, leaving the rest
    /// of what someone wrote untouched.
    private func replaceInValue(_ element: AXUIElement, original: String, with correction: String) -> Bool {
        guard var value = copy(element, kAXValueAttribute) as? String,
              let range = value.range(of: original)
        else { return false }
        value.replaceSubrange(range, with: correction)
        return set(element, kAXValueAttribute, to: value)
    }

    /// Last resort. Only works when the text to replace is selected, which is
    /// exactly the case the Accessibility path could not handle.
    ///
    /// Declines when the clipboard holds anything but text, rather than reading
    /// someone's copied photo or file to save it. Failing to apply a correction
    /// is a far smaller cost than that.
    private func paste(_ correction: String) -> Outcome {
        do {
            try PasteboardGuard.borrowingTextClipboard {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(correction, forType: .string)
                sendCommandV()
                // The paste is asynchronous in the target app. Restoring the
                // clipboard instantly would race it, so give the app a moment.
                Thread.sleep(forTimeInterval: 0.15)
            }
            return .applied
        } catch {
            return .failed
        }
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(9)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 1.0)
        guard let value = copy(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        return (value as! AXUIElement)
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    private func set(_ element: AXUIElement, _ attribute: String, to value: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success,
              settable.boolValue
        else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef) == .success
    }
}
