import Foundation

/// What the Accessibility layer managed to read from the focused field.
/// Everything is optional because coverage varies wildly between apps.
public struct FocusedText: Sendable, Equatable {
    public let value: String?
    public let selectedText: String?
    public let caretOffset: Int?
    public let appBundleID: String
    public let isSecureField: Bool

    public init(
        value: String?, selectedText: String?, caretOffset: Int?,
        appBundleID: String, isSecureField: Bool
    ) {
        self.value = value
        self.selectedText = selectedText
        self.caretOffset = caretOffset
        self.appBundleID = appBundleID
        self.isSecureField = isSecureField
    }
}

public enum NothingReason: String, Sendable, Equatable {
    case secureField
    case noReadableText
    /// The element answered a value but has no notion of a selection, so what it
    /// answered is a screen dump rather than a field someone is typing in.
    case noSelectionExposed

    /// Whether borrowing the clipboard is worth trying after this. A password
    /// field is never copied, whatever else might be selected on screen.
    public var allowsClipboardFallback: Bool { self != .secureField }
}

public enum CheckTarget: Sendable, Equatable {
    case selection(String)
    /// A selection that Accessibility never exposed, taken with a synthesized
    /// copy. Kept apart from `.selection` because the app it came from has no
    /// editable field to write a correction back into.
    case copiedSelection(String)
    case sentence(String, previous: String?)
    case nothing(NothingReason)
}

/// Decides what the hotkey actually checks, given whatever the Accessibility
/// layer managed to read. Pure, so the ladder is testable without a running app.
public enum CheckTargetResolver {
    public static func resolve(_ focused: FocusedText) -> CheckTarget {
        if focused.isSecureField { return .nothing(.secureField) }

        // A deliberate selection beats inference from the caret.
        let selection = focused.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selection, !selection.isEmpty { return .selection(selection) }

        guard let value = focused.value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .nothing(.noReadableText)
        }

        // An element that answers no AXSelectedText at all has no notion of a
        // selection, which means its value is not a field being edited. Ghostty
        // answers eight hundred characters of terminal screen with the caret
        // pinned at 0, so the sentence at that caret is a random line someone
        // never wrote. Leave it to the clipboard rather than check the wrong
        // text and send a stranger's terminal to the model.
        guard focused.selectedText != nil else { return .nothing(.noSelectionExposed) }

        // With no caret position, treat it as sitting at the end. That yields the
        // last sentence, which is what someone just finished typing. Sending the
        // whole field instead would hand a single-sentence prompt several
        // sentences at once and degrade the judgement.
        let caret = focused.caretOffset ?? value.count
        guard let extracted = SentenceExtractor.extract(from: value, caretOffset: caret) else {
            return .nothing(.noReadableText)
        }
        return .sentence(extracted.sentence, previous: extracted.previous)
    }
}
