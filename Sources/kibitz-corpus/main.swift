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
        let note: String?
    }
    let cases: [Case]
}

let path = CommandLine.arguments.dropFirst().first ?? "Corpus/corpus.json"
let concurrency = Int(CommandLine.arguments.dropFirst(2).first ?? "4") ?? 4

let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
let prompt = try BundledPrompt.renderedSystemPrompt(for: .polish)
let provider = ClaudeCodeProvider(systemPrompt: prompt)

struct Outcome: Sendable {
    let index: Int
    let sentence: String
    let expected: String
    let expectedCategory: String?
    let note: String?
    let verdict: Verdict?
    let error: String?
    let costUSD: Double
}

print("running \(corpus.cases.count) cases, \(concurrency) at a time")
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
                               note: item.element.note, verdict: response.verdict, error: nil,
                               costUSD: response.costUSD)
            } catch {
                return Outcome(index: item.offset, sentence: item.element.sentence,
                               expected: item.element.expect, expectedCategory: item.element.category,
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
if failures > 0 { print("request errors  \(failures)") }
print(String(format: "cost            $%.2f over %.0fs", totalCost, Date().timeIntervalSince(started)))

// A tool that interrupts correct writing gets ignored, so that is the gate.
if falsePositives > 1 || failures > 0 {
    print("\nFAIL: too many false positives or request errors")
    exit(1)
}
print("\nPASS")
