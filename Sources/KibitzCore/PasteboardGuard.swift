import AppKit

/// Borrows the clipboard for a paste, and only when that is safe to do.
///
/// An earlier version copied every representation of every clipboard item so it
/// could restore them perfectly. That was a mistake: calling `data(forType:)` on
/// a file URL or an image materialises it, and macOS then demands Photos and
/// network volume permissions in this app's name. A writing assistant has no
/// business reading either.
///
/// So the rule is narrow: if the clipboard holds anything that is not text, the
/// clipboard is left completely alone and the caller is told no.
public enum PasteboardGuard {

    public enum Refusal: Error, Equatable {
        case clipboardHoldsNonTextContent
    }

    /// Types that are safe to read and restore. Everything else is off limits.
    private static let textTypes: Set<NSPasteboard.PasteboardType> = [
        .string, .rtf, .rtfd, .html, .tabularText,
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.text"),
        NSPasteboard.PasteboardType("com.apple.notes.richtext")
    ]

    @discardableResult
    public static func borrowingTextClipboard<T>(
        of pasteboard: NSPasteboard = .general,
        _ body: () throws -> T
    ) throws -> T {
        let items = pasteboard.pasteboardItems ?? []

        // Inspect type names only. Never touch the data of an unknown type.
        for item in items where !item.types.allSatisfy(textTypes.contains) {
            throw Refusal.clipboardHoldsNonTextContent
        }

        let saved = items.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types where textTypes.contains(type) {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }

        defer {
            pasteboard.clearContents()
            // An empty snapshot means it started empty. Writing an item back would
            // leave our own residue behind.
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
        return try body()
    }
}
