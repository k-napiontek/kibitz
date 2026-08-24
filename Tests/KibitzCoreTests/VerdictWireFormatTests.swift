import Foundation
import Testing
@testable import KibitzCore
@Suite("Verdict wire format")
struct VerdictWireFormatTests {

    @Test("decodes why_l1, the language-neutral field name")
    func decodesWhyL1() throws {
        let json = #"{"verdict":"error","category":"article","severity":"high","corrected":"an email","why_l1":"Potrzebny przedimek."}"#

        let verdict = try JSONDecoder().decode(Verdict.self, from: Data(json.utf8))

        #expect(verdict.whyL1 == "Potrzebny przedimek.")
    }
}
