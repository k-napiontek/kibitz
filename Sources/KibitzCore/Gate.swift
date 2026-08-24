import Foundation
import NaturalLanguage

/// How a sentence arrived for checking.
public enum CaptureSource: Sendable, Equatable {
    /// The writer pressed the hotkey and is waiting for an answer.
    case hotkey
    /// Background observation of an allowlisted app.
    case automatic
}

/// Everything the gate needs, already resolved by the caller.
///
/// The gate performs no I/O of its own so that it stays fast enough to run on
/// every finished sentence, and exhaustively testable without a running app.
public struct GateInput: Sendable {
    public let sentence: String
    public let appBundleID: String
    public let isSecureInputActive: Bool
    public let isSecureField: Bool
    public let source: CaptureSource

    public init(
        sentence: String,
        appBundleID: String,
        isSecureInputActive: Bool,
        isSecureField: Bool,
        source: CaptureSource
    ) {
        self.sentence = sentence
        self.appBundleID = appBundleID
        self.isSecureInputActive = isSecureInputActive
        self.isSecureField = isSecureField
        self.source = source
    }
}

public enum SkipReason: String, Sendable, Equatable {
    case secureInputActive
    case secureField
    case appNotAllowed
    case tooShort
    case alreadyChecked
    case notEnglish
    case looksLikeCode
}

public enum GateDecision: Sendable, Equatable {
    case check
    case skip(SkipReason)
}

public struct Gate: Sendable {
    private let allowlist: Set<String>
    private let minimumWords: Int
    private var seen: SeenCache

    public init(allowlist: Set<String>, minimumWords: Int = 4, dedupeCapacity: Int = 500) {
        self.allowlist = allowlist
        self.minimumWords = minimumWords
        self.seen = SeenCache(capacity: dedupeCapacity)
    }

    /// Rules are ordered cheapest-first, except the two privacy stops which
    /// always come first and are deliberately not configurable.
    public mutating func decide(_ input: GateInput) -> GateDecision {
        if input.isSecureInputActive { return .skip(.secureInputActive) }
        if input.isSecureField { return .skip(.secureField) }

        if input.source == .automatic, !allowlist.contains(input.appBundleID) {
            return .skip(.appNotAllowed)
        }
        if Self.wordCount(input.sentence) < minimumWords { return .skip(.tooShort) }
        if Self.looksLikeCode(input.sentence) { return .skip(.looksLikeCode) }

        let key = Self.normalize(input.sentence)
        if seen.contains(key) { return .skip(.alreadyChecked) }
        if !Self.isEnglish(input.sentence) { return .skip(.notEnglish) }

        seen.insert(key)
        return .check
    }

    static func wordCount(_ sentence: String) -> Int {
        sentence.split(whereSeparator: \.isWhitespace).count
    }

    /// Collapses case and whitespace so that retyping the same sentence with
    /// different spacing still counts as already checked.
    static func normalize(_ sentence: String) -> String {
        sentence
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static let codePunctuation: Set<Character> = ["{", "}", ";"]
    private static let codeOperators = ["://", "=>", "->", "::"]

    /// Cheap structural heuristics, deliberately not a parser. Runs on every
    /// sentence, so it uses plain scanning rather than regex.
    static func looksLikeCode(_ sentence: String) -> Bool {
        if codeOperators.contains(where: { sentence.contains($0) }) { return true }
        if sentence.contains(where: { codePunctuation.contains($0) }) { return true }
        if containsPathToken(sentence) { return true }
        return containsCallSyntax(sentence)
    }

    /// A token that opens with `/` or `~/` and carries a further separator.
    /// Plain prose words like "and/or" do not qualify.
    private static func containsPathToken(_ sentence: String) -> Bool {
        for token in sentence.split(whereSeparator: \.isWhitespace) {
            var rest = token
            if rest.hasPrefix("~/") {
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("/") {
                rest = rest.dropFirst()
            } else {
                continue
            }
            if rest.contains("/") { return true }
        }
        return false
    }

    /// An identifier character immediately followed by `(`, as in `decide(`.
    /// Prose keeps a space before a parenthesis, as in "the details (roughly)".
    private static func containsCallSyntax(_ sentence: String) -> Bool {
        var previous: Character?
        for character in sentence {
            if character == "(", let previous, previous.isLetter || previous.isNumber || previous == "_" {
                return true
            }
            previous = character
        }
        return false
    }

    static func isEnglish(_ sentence: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sentence)
        return recognizer.dominantLanguage == .english
    }
}

/// Fixed-capacity set that evicts the oldest key first.
struct SeenCache: Sendable {
    private let capacity: Int
    private var keys: Set<String> = []
    private var order: [String] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func contains(_ key: String) -> Bool {
        keys.contains(key)
    }

    mutating func insert(_ key: String) {
        guard !keys.contains(key) else { return }
        keys.insert(key)
        order.append(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            keys.remove(evicted)
        }
    }
}
