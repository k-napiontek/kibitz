import AppKit
import Testing
@testable import KibitzCore

@Suite("PasteboardGuard")
struct PasteboardGuardTests {

    /// Never the general pasteboard: a test must not destroy what the person
    /// running it had copied.
    private func scratchPasteboard(_ label: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("kibitz.test.\(label).\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    struct Boom: Error {}

    @Test("what was on the clipboard is put back afterwards")
    func restoresPreviousContents() {
        let board = scratchPasteboard("restore")
        board.setString("something the user copied", forType: .string)

        PasteboardGuard.preservingContents(of: board) {
            board.clearContents()
            board.setString("the selection we grabbed", forType: .string)
        }

        #expect(board.string(forType: .string) == "something the user copied")
    }

    @Test("the clipboard is restored even when the check throws")
    func restoresOnThrow() {
        let board = scratchPasteboard("throw")
        board.setString("precious", forType: .string)

        #expect(throws: Boom.self) {
            try PasteboardGuard.preservingContents(of: board) {
                board.clearContents()
                board.setString("garbage", forType: .string)
                throw Boom()
            }
        }

        #expect(board.string(forType: .string) == "precious")
    }

    @Test("the body's result is returned to the caller")
    func returnsBodyResult() {
        let board = scratchPasteboard("result")

        let grabbed = PasteboardGuard.preservingContents(of: board) { () -> String in
            board.clearContents()
            board.setString("I am interested of this.", forType: .string)
            return board.string(forType: .string) ?? ""
        }

        #expect(grabbed == "I am interested of this.")
    }

    @Test("non-text clipboard contents survive too, not just strings")
    func restoresRichContent() {
        let board = scratchPasteboard("rich")
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setData(Data("{\\rtf1 rich}".utf8), forType: .rtf)
        board.clearContents()
        board.writeObjects([item])

        PasteboardGuard.preservingContents(of: board) {
            board.clearContents()
            board.setString("clobbered", forType: .string)
        }

        #expect(board.string(forType: .string) == "plain")
        #expect(board.data(forType: .rtf) != nil)
    }

    @Test("an empty clipboard is left empty, not filled with our leftovers")
    func emptyStaysEmpty() {
        let board = scratchPasteboard("empty")

        PasteboardGuard.preservingContents(of: board) {
            board.clearContents()
            board.setString("temporary", forType: .string)
        }

        #expect(board.string(forType: .string) == nil)
    }
}
