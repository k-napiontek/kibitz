import Testing
@testable import KibitzCore

@Suite("ClaudeCodeProvider")
struct ClaudeCodeProviderTests {

    private let provider = ClaudeCodeProvider(
        systemPrompt: "RENDERED PROMPT for a Polish-speaking engineer.",
        model: "sonnet"
    )

    @Test("the subscription backend cannot serve automatic mode")
    func doesNotSupportAutomaticMode() {
        #expect(provider.supportsAutomaticMode == false)
    }

    @Test("strips tools, MCP servers and session persistence from the invocation")
    func buildsMinimalInvocation() {
        let arguments = provider.arguments(for: "Hello there my friend.", previous: nil)

        #expect(arguments.contains("--print"))
        #expect(arguments.contains("--output-format"))
        #expect(arguments.contains("json"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(arguments.contains("--max-turns"))
        #expect(arguments.contains("--system-prompt"))
        #expect(arguments.contains("RENDERED PROMPT for a Polish-speaking engineer."))
    }

    @Test("pins the model rather than inheriting whatever the CLI defaults to")
    func pinsTheModel() {
        let arguments = provider.arguments(for: "Hello there my friend.", previous: nil)
        let modelIndex = try? #require(arguments.firstIndex(of: "--model"))

        #expect(modelIndex != nil)
        if let modelIndex { #expect(arguments[modelIndex + 1] == "sonnet") }
    }

    @Test("the sentence is passed as an argument, not interpolated into a shell string")
    func passesSentenceAsArgument() {
        let nasty = "He said \"rm -rf /\" and I; laughed."

        let arguments = provider.arguments(for: nasty, previous: nil)

        #expect(arguments.contains("NONE\n---\n" + nasty))
    }
}
