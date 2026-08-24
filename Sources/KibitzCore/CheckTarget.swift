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
}

public enum CheckTarget: Sendable, Equatable {
    case selection(String)
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
