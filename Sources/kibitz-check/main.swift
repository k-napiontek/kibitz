import Foundation
import KibitzCore

// Development harness for the core pipeline. Checks one sentence end to end
// and prints what the popup would show, plus the numbers that decide which
// backend is worth using: wall time, cost, and how much of the prompt the
// cache served.

let raw = Array(CommandLine.arguments.dropFirst())

/// Reads `--name value` out of the arguments and returns what is left, so the
/// sentence can still be given positionally.
func option(_ name: String, in arguments: inout [String]) -> String? {
    guard let flag = arguments.firstIndex(of: "--\(name)"),
          flag + 1 < arguments.count
    else { return nil }
    let value = arguments[flag + 1]
    arguments.removeSubrange(flag...(flag + 1))
    return value
}

var arguments = raw
let backendName = option("backend", in: &arguments)
let modelName = option("model", in: &arguments)

let usage = """
usage: kibitz-check <sentence> [previous] [--backend subscription|deepseek] [--model flash|pro]
"""

guard let sentence = arguments.first else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
let previous = arguments.count > 1 ? arguments[1] : nil

// An unrecognised name is a typo, not a reason to silently run the default
// backend and report numbers for the wrong thing.
var backend: Backend?
if let backendName {
    guard let parsed = Backend(rawValue: backendName) else {
        FileHandle.standardError.write(Data("unknown backend '\(backendName)'\n\(usage)\n".utf8))
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
        FileHandle.standardError.write(Data("unknown model '\(modelName)'\n\(usage)\n".utf8))
        exit(2)
    }
    model = parsed
}

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
let filter = VerdictFilter(config: .default)

let started = Date()
let response: CheckResponse
do {
    response = try await provider.run(sentence: sentence, previous: previous)
} catch {
    // A backend failure is a result, not a crash. The stack trace a top level
    // `try` prints tells you nothing you want to know here.
    FileHandle.standardError.write(Data("backend   : \(provider.displayName)\ncheck failed: \(error)\n".utf8))
    exit(1)
}
let elapsed = Date().timeIntervalSince(started)

print("backend   : \(provider.displayName)")
print("sentence  : \(sentence)")
print("verdict   : \(response.verdict.outcome.rawValue)  [\(response.verdict.category.rawValue), \(response.verdict.severity.rawValue)]")
print("corrected : \(response.verdict.corrected)")
print("why_l1    : \(response.verdict.whyL1.isEmpty ? "-" : response.verdict.whyL1)")
// Both paths, because the muting rules only ever applied to automatic checking
// and this harness is how that path gets judged when it lands.
let onHotkey = filter.apply(response.verdict, source: .hotkey) == .show
let whileTyping = filter.apply(response.verdict, source: .automatic) == .show
print("popup     : \(onHotkey ? "SHOWN" : "suppressed")  (automatic: \(whileTyping ? "shown" : "suppressed"))")
print("tokens    : \(response.cacheReadTokens) cached, \(response.uncachedInputTokens) fresh")
// DeepSeek returns no cost of its own, so that figure is computed from list
// prices and is an upper bound. The CLI reports what it actually billed.
let costNote = provider is DeepSeekProvider ? " est." : ""
print(String(format: "timing    : %.2fs wall, %dms api, $%.4f%@",
             elapsed, response.apiDurationMS, response.costUSD, costNote))
