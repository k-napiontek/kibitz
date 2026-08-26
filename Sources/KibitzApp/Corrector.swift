import AppKit
import ApplicationServices
import KibitzCore

/// Puts an accepted correction back into the field it came from.
///
/// Tries Accessibility first because it is precise and invisible. Falls back to
/// a paste, which always borrows the clipboard through `PasteboardGuard` so the
/// person gets their own clipboard back.
struct Corrector {

    enum Outcome { case applied, copied, failed }

    func apply(correction: String, replacing original: String, target: CheckTarget) -> Outcome {
        // Handled before an element is even resolved: the text came from a
        // synthesized copy, so there is no field here to write into.
        if case .copiedSelection = target { return handOff(correction) }

        guard let focused = focusedElement() else { return .failed }

        switch target {
        case .selection:
            if set(focused, kAXSelectedTextAttribute, to: correction) { return .applied }
        case .sentence:
            if replaceInValue(focused, original: original, with: correction) { return .applied }
        case .copiedSelection, .nothing:
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

    /// Hands the correction over instead of writing it anywhere.
    ///
    /// Reached only for text taken with a synthesized copy, which means the app
    /// exposed no editable field at all. A paste there does not replace the
    /// original: a terminal has no writable selection, so Cmd+V would drop the
    /// correction next to what someone typed and garble the line. Leaving it on
    /// the clipboard is the one thing that is always useful, and unlike the
    /// borrow below the text is meant to stay there - that is what was asked for.
    private func handOff(_ correction: String) -> Outcome {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(correction, forType: .string)
        return .copied
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
                Keystroke.commandV()
                // The paste is asynchronous in the target app. Restoring the
                // clipboard instantly would race it, so give the app a moment.
                Thread.sleep(forTimeInterval: 0.15)
            }
            return .applied
        } catch {
            return .failed
        }
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
