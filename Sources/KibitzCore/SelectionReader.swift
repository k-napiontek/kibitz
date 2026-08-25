import AppKit

/// Reads a selection out of an app that exposes nothing to Accessibility.
///
/// The last rung of the ladder, for terminals and for browsers that refuse even
/// after being asked. It borrows the clipboard through `PasteboardGuard`, which
/// declines outright when the clipboard holds anything but text and puts back
/// what was there - the same rules `Corrector` follows when pasting a correction.
public struct SelectionReader {

    /// How long an app is given to service the copy. A real copy lands in tens
    /// of milliseconds; this bound only exists so a silent app cannot hang the
    /// hotkey.
    static let timeout: TimeInterval = 0.25
    private static let pollInterval: TimeInterval = 0.01

    private let pasteboard: NSPasteboard
    private let copy: () -> Void

    public init(pasteboard: NSPasteboard = .general, copy: @escaping () -> Void = Keystroke.commandC) {
        self.pasteboard = pasteboard
        self.copy = copy
    }

    /// The selected text, or nil when nothing was selected or the clipboard was
    /// not ours to borrow.
    public func copySelection() -> String? {
        let copied = try? PasteboardGuard.borrowingTextClipboard(of: pasteboard) {
            // Cleared first, so a value left over from an earlier copy cannot be
            // mistaken for the current selection.
            pasteboard.clearContents()
            let before = pasteboard.changeCount
            copy()

            // An app with no selection services the copy by doing nothing, and
            // the change count is the only way to tell that apart from a copy
            // that has simply not landed yet.
            let deadline = Date().addingTimeInterval(Self.timeout)
            while pasteboard.changeCount == before, Date() < deadline {
                Thread.sleep(forTimeInterval: Self.pollInterval)
            }
            guard pasteboard.changeCount != before else { return String?.none }

            let text = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        }
        return copied ?? nil
    }
}
