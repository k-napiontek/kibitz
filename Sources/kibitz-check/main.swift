import Foundation
import KibitzCore

// Development harness for the core pipeline. Checks one sentence end to end
// against the Claude Max subscription and prints what the popup would show.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let sentence = arguments.first else {
    FileHandle.standardError.write(Data("usage: englishcoach-check <sentence> [previous]\n".utf8))
    exit(2)
}
let previous = arguments.count > 1 ? arguments[1] : nil

let prompt = try BundledPrompt.renderedSystemPrompt(for: .polish)
let provider = ClaudeCodeProvider(systemPrompt: prompt)
let filter = VerdictFilter(config: .default)

let started = Date()
let response = try await provider.run(sentence: sentence, previous: previous)
let elapsed = Date().timeIntervalSince(started)

print("sentence  : \(sentence)")
print("verdict   : \(response.verdict.outcome.rawValue)  [\(response.verdict.category.rawValue), \(response.verdict.severity.rawValue)]")
print("corrected : \(response.verdict.corrected)")
print("why_l1    : \(response.verdict.whyL1.isEmpty ? "-" : response.verdict.whyL1)")
print("popup     : \(filter.apply(response.verdict) == .show ? "SHOWN" : "suppressed")")
print(String(format: "timing    : %.2fs wall, %dms api, $%.4f, %d cached tokens",
             elapsed, response.apiDurationMS, response.costUSD, response.cacheReadTokens))
