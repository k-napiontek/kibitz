import Foundation
import NaturalLanguage

public struct ExtractedSentence: Sendable, Equatable {
    public let sentence: String
    public let previous: String?
}

/// Splits text into sentences using `NLTokenizer` rather than punctuation
/// rules, so abbreviations and decimal numbers do not create false boundaries.
public enum SentenceExtractor {

    static func ranges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var found: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if !text[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append(range)
            }
            return true
        }
        return found
    }

    public static func sentences(in text: String) -> [String] {
        ranges(in: text).map {
            text[$0].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Picks the sentence the caret sits in, with the one before it as context.
    /// A caret past the end is clamped, because callers get their offsets from
    /// the Accessibility API and those can lag the text by a keystroke.
    public static func extract(from text: String, caretOffset: Int) -> ExtractedSentence? {
        let found = ranges(in: text)
        guard !found.isEmpty else { return nil }

        let clamped = min(max(caretOffset, 0), text.count)
        let caretIndex = text.index(text.startIndex, offsetBy: clamped)

        let position = found.firstIndex { caretIndex >= $0.lowerBound && caretIndex <= $0.upperBound }
            ?? found.indices.last!

        func clean(_ range: Range<String.Index>) -> String {
            text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sentence = clean(found[position])
        guard !sentence.isEmpty else { return nil }

        let previous = position > found.startIndex ? clean(found[position - 1]) : nil
        return ExtractedSentence(sentence: sentence, previous: previous)
    }
}
