import Foundation

/// Word-level diff, so the popup can show what actually changed instead of
/// making the reader compare two sentences themselves.
///
/// Spans cover the corrected sentence only. Deletions are invisible by design:
/// what matters to a learner is what the sentence should say, with the parts
/// they got wrong marked.
public enum SentenceDiff {

    public struct Span: Sendable, Equatable {
        public let text: String
        public let isChanged: Bool

        public init(text: String, isChanged: Bool) {
            self.text = text
            self.isChanged = isChanged
        }
    }

    public static func spans(original: String, corrected: String) -> [Span] {
        let old = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let new = corrected.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let kept = longestCommonSubsequence(old, new)

        var spans: [Span] = []
        var keptIndex = kept.startIndex

        for (position, word) in new.enumerated() {
            let isKept = keptIndex < kept.endIndex && kept[keptIndex] == word
            if isKept { keptIndex += 1 }

            if position > 0 { spans.append(Span(text: " ", isChanged: false)) }
            guard !word.isEmpty else { continue }
            spans.append(Span(text: word, isChanged: !isKept))
        }
        return merge(spans)
    }

    /// Standard LCS. Sentences are short, so the quadratic table is free.
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [String] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(a[i]); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    /// Adjacent spans of the same kind become one, so the popup does not draw a
    /// separate highlight box per word in a rewritten phrase.
    private static func merge(_ spans: [Span]) -> [Span] {
        spans.reduce(into: [Span]()) { result, span in
            if let last = result.last, last.isChanged == span.isChanged {
                result[result.count - 1] = Span(text: last.text + span.text, isChanged: last.isChanged)
            } else {
                result.append(span)
            }
        }
    }
}
