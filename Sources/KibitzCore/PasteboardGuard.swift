import AppKit

/// Borrows the clipboard and always gives it back.
///
/// Reading a selection out of an app that exposes nothing to the Accessibility
/// API means sending Cmd+C and reading the pasteboard. Destroying whatever the
/// person had copied is the kind of bug that gets an app uninstalled, so the
/// restore runs on every path out, including a thrown error.
public enum PasteboardGuard {

    @discardableResult
    public static func preservingContents<T>(
        of pasteboard: NSPasteboard = .general,
        _ body: () throws -> T
    ) rethrows -> T {
        let saved = snapshot(of: pasteboard)
        defer { restore(saved, to: pasteboard) }
        return try body()
    }

    /// Copies every representation of every item. Keeping only the string would
    /// silently downgrade copied rich text, images or files to nothing.
    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        // An empty snapshot means the clipboard started empty. Leaving it cleared
        // is correct; writing an empty item would leave our own residue behind.
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
