import Testing
@testable import KibitzCore

@Suite("VerdictDecoder")
struct VerdictDecoderTests {

    private let bare = #"{"verdict":"ok","category":"none","severity":"low","corrected":"Let's ship it.","why_l1":""}"#

    @Test("decodes the reply the prompt asks for")
    func decodesBareObject() throws {
        let verdict = try #require(VerdictDecoder.decode(from: bare))

        #expect(verdict.outcome == .ok)
        #expect(verdict.corrected == "Let's ship it.")
    }

    @Test("tolerates surrounding whitespace")
    func decodesPaddedObject() {
        #expect(VerdictDecoder.decode(from: "\n  " + bare + "  \n") != nil)
    }

    @Test("unwraps a markdown fence, which both backends produce despite the prompt")
    func decodesFencedObject() throws {
        let verdict = try #require(VerdictDecoder.decode(from: "```json\n" + bare + "\n```"))

        #expect(verdict.outcome == .ok)
    }

    @Test("survives a stray sentence around the object")
    func decodesObjectWithProse() throws {
        let verdict = try #require(
            VerdictDecoder.decode(from: "Here is the result:\n" + bare + "\nHope that helps.")
        )

        #expect(verdict.corrected == "Let's ship it.")
    }

    @Test("a reply with no object at all decodes to nothing rather than guessing")
    func rejectsProseOnly() {
        #expect(VerdictDecoder.decode(from: "I'm not sure what you mean.") == nil)
    }

    @Test("a truncated object is not half a verdict")
    func rejectsTruncatedObject() {
        #expect(VerdictDecoder.decode(from: #"{"verdict":"error","corrected":"I am 20 years"#) == nil)
    }
}
