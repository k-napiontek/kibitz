import Foundation
import KibitzCore

// Prompt quality gate. Runs the corpus through a provider and reports the two
// numbers that matter: how many real mistakes were caught, and how often a
// correct sentence was flagged. The second number is the important one.

struct Corpus: Decodable {
    struct Case: Decodable {
        let sentence: String
        let expect: String
        let category: String?
        /// Every rewrite that counts as right, listed generously. Optional
        /// because it only means something on an `error` case.
        ///
        /// The category alone never caught the failure this exists for: a
        /// verdict can name the right category and still hand back a sentence
        /// nobody could send. Free-form English makes a single golden string
        /// brittle, so the answer is a set, and widening it is the normal fix
        /// when a phrasing is genuinely fine.
        let corrected: [String]?
        let note: String?
    }
    let cases: [Case]
}

/// Collapses runs of whitespace so a corpus entry wrapped across lines still
/// matches. Everything else, case and punctuation included, has to be right:
/// those are exactly what the tool is being graded on.
func normalized(_ sentence: String) -> String {
    sentence.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Reads `--name value` out of the arguments, leaving the positional path and
/// concurrency where they were.
func option(_ name: String, in arguments: inout [String]) -> String? {
    guard let flag = arguments.firstIndex(of: "--\(name)"),
          flag + 1 < arguments.count
    else { return nil }
    let value = arguments[flag + 1]
    arguments.removeSubrange(flag...(flag + 1))
    return value
}

var arguments = Array(CommandLine.arguments.dropFirst())
let backendName = option("backend", in: &arguments)
let modelName = option("model", in: &arguments)

let path = arguments.first ?? "Corpus/corpus.json"
let concurrency = Int(arguments.dropFirst().first ?? "4") ?? 4

// An unrecognised name is a typo. Grading the wrong backend and calling it a
// pass is worse than refusing to start.
var backend: Backend?
if let backendName {
    guard let parsed = Backend(rawValue: backendName) else {
        FileHandle.standardError.write(Data("unknown backend '\(backendName)'\n".utf8))
        exit(2)
    }
    backend = parsed
}
var model: DeepSeekModel?
if let modelName {
    let named = modelName == "flash" ? DeepSeekModel.flash.rawValue
        : modelName == "pro" ? DeepSeekModel.pro.rawValue
        : modelName
    guard let parsed = DeepSeekModel(rawValue: named) else {
        FileHandle.standardError.write(Data("unknown model '\(modelName)'\n".utf8))
        exit(2)
    }
    model = parsed
}

let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
/// The two ways to get a key into the Keychain, in the order worth trying.
let keyHelp = """
no DeepSeek key in the Keychain. Set one from the kibitz menu, or:
  security add-generic-password -U -s com.knapiontek.kibitz -a deepseek -w <key>
"""

let provider: any ModelProvider
do {
    provider = try ProviderResolver.make(backend: backend, model: model)
} catch ProviderResolutionError.noAPIKey {
    FileHandle.standardError.write(Data((keyHelp + "\n").utf8))
    exit(2)
}

struct Outcome: Sendable {
    let index: Int
    let sentence: String
    let expected: String
    let expectedCategory: String?
    let expectedCorrections: [String]?
    let note: String?
    let verdict: Verdict?
    let error: String?
    let costUSD: Double
}

print("running \(corpus.cases.count) cases, \(concurrency) at a time, on \(provider.displayName)")
let started = Date()

let outcomes: [Outcome] = await withTaskGroup(of: Outcome.self) { group in
    var pending = Array(corpus.cases.enumerated())
    var running = 0
    var results: [Outcome] = []

    func launch(_ item: (offset: Int, element: Corpus.Case)) {
        FileHandle.standardError.write(Data("\nstart #\(item.offset) \(item.element.sentence.prefix(40))\n".utf8))
        group.addTask {
            do {
                let response = try await provider.run(sentence: item.element.sentence, previous: nil)
                return Outcome(index: item.offset, sentence: item.element.sentence,
                               expected: item.element.expect, expectedCategory: item.element.category,
                               expectedCorrections: item.element.corrected,
                               note: item.element.note, verdict: response.verdict, error: nil,
                               costUSD: response.costUSD)
            } catch {
                return Outcome(index: item.offset, sentence: item.element.sentence,
                               expected: item.element.expect, expectedCategory: item.element.category,
                               expectedCorrections: item.element.corrected,
                               note: item.element.note, verdict: nil,
                               error: String(describing: error), costUSD: 0)
            }
        }
    }

    while running < concurrency, !pending.isEmpty { launch(pending.removeFirst()); running += 1 }
    for await result in group {
        results.append(result)
        FileHandle.standardError.write(Data("done #\(result.index) (\(results.count)/\(corpus.cases.count))\n".utf8))
        if !pending.isEmpty { launch(pending.removeFirst()) }
    }
    return results.sorted { $0.index < $1.index }
}

print("\n" + String(repeating: "=", count: 76))

var caught = 0, missed = 0, falsePositives = 0, correctlyQuiet = 0
var categoryHits = 0, categoryTotal = 0, failures = 0
var correctionHits = 0, correctionTotal = 0
var totalCost = 0.0

for o in outcomes {
    totalCost += o.costUSD
    guard let v = o.verdict else {
        failures += 1
        print("ERROR  \(o.sentence)\n       \(o.error ?? "?")")
        continue
    }
    let flagged = v.outcome == .error
    switch (o.expected, flagged) {
    case ("error", true):
        caught += 1
        categoryTotal += 1
        if v.category.rawValue == o.expectedCategory { categoryHits += 1 }
        else { print("category  expected \(o.expectedCategory ?? "?") got \(v.category.rawValue)  |  \(o.sentence)") }
        if let acceptable = o.expectedCorrections, !acceptable.isEmpty {
            correctionTotal += 1
            if acceptable.map(normalized).contains(normalized(v.corrected)) {
                correctionHits += 1
            } else {
                print("CORRECTION  \(o.sentence)")
                print("            got      \(v.corrected)")
                for candidate in acceptable { print("            accepted \(candidate)") }
            }
        }
    case ("error", false):
        missed += 1
        print("MISSED    \(o.sentence)")
    case ("ok", true):
        falsePositives += 1
        print("FALSE POSITIVE  \(o.sentence)")
        print("                -> \(v.corrected)")
        print("                   [\(v.category.rawValue)] \(v.whyL1)")
        if let n = o.note { print("                   note: \(n)") }
    default:
        correctlyQuiet += 1
    }
}

let errorTotal = caught + missed
let okTotal = falsePositives + correctlyQuiet
print(String(repeating: "=", count: 76))
func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "n/a" : String(format: "%.0f%%", Double(a) / Double(b) * 100) }
print("caught          \(caught)/\(errorTotal)  (\(pct(caught, errorTotal)))")
print("FALSE POSITIVES \(falsePositives)/\(okTotal)  (\(pct(falsePositives, okTotal)))   <- the number that matters")
print("category match  \(categoryHits)/\(categoryTotal)  (\(pct(categoryHits, categoryTotal)))")
print("correction match \(correctionHits)/\(correctionTotal)  (\(pct(correctionHits, correctionTotal)))")
if failures > 0 { print("request errors  \(failures)") }
print(String(format: "cost            $%.2f over %.0fs", totalCost, Date().timeIntervalSince(started)))

// A tool that interrupts correct writing gets ignored, so that is the first
// gate. The second is that a correction has to be a sentence you could send:
// under-correcting to match the category you named was invisible here for as
// long as only the category was graded.
if falsePositives > 1 || failures > 0 {
    print("\nFAIL: too many false positives or request errors")
    exit(1)
}
if correctionHits < correctionTotal {
    print("\nFAIL: \(correctionTotal - correctionHits) correction(s) outside the accepted set")
    exit(1)
}
print("\nPASS")
