import AppKit
import Testing
@testable import KibitzCore

@Suite("SelectionReader")
struct SelectionReaderTests {

    /// Never the general pasteboard: a test must not destroy what the person
    /// running it had copied.
    private func scratchPasteboard(_ label: String) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("kibitz.test.\(label).\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test("returns what the copy put on the clipboard")
    func readsTheCopiedSelection() {
        let board = scratchPasteboard("copied")
        let reader = SelectionReader(pasteboard: board) {
            board.clearContents()
            board.setString("The tests was failing.", forType: .string)
        }

        #expect(reader.copySelection() == "The tests was failing.")
    }

    @Test("nothing selected means nothing copied, and no answer invented")
    func answersNothingWhenNothingWasCopied() {
        let board = scratchPasteboard("nothing")
        // An app with no selection services the copy by doing nothing at all,
        // so the change count never moves.
        let reader = SelectionReader(pasteboard: board) {}

        #expect(reader.copySelection() == nil)
    }

    @Test("what was on the clipboard is put back")
    func restoresTheClipboard() {
        let board = scratchPasteboard("restore")
        board.setString("something the user copied", forType: .string)
        let reader = SelectionReader(pasteboard: board) {
            board.clearContents()
            board.setString("the selection we grabbed", forType: .string)
        }

        _ = reader.copySelection()

        #expect(board.string(forType: .string) == "something the user copied")
    }

    @Test("a clipboard holding anything but text is left completely alone")
    func refusesToTouchNonTextContent() {
        let board = scratchPasteboard("image")
        board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        var copied = false
        let reader = SelectionReader(pasteboard: board) { copied = true }

        #expect(reader.copySelection() == nil)
        // Not merely refused: the copy is never even attempted, so nothing can
        // overwrite what was there.
        #expect(copied == false)
        #expect(board.data(forType: .png) != nil)
    }

    @Test("whitespace around a copied selection is not a sentence")
    func ignoresAWhitespaceOnlySelection() {
        let board = scratchPasteboard("blank")
        let reader = SelectionReader(pasteboard: board) {
            board.clearContents()
            board.setString("   \n  ", forType: .string)
        }

        #expect(reader.copySelection() == nil)
    }

    @Test("the copied selection is trimmed, since a drag usually takes a space")
    func trimsTheSelection() {
        let board = scratchPasteboard("trim")
        let reader = SelectionReader(pasteboard: board) {
            board.clearContents()
            board.setString("  Let's ship it.  ", forType: .string)
        }

        #expect(reader.copySelection() == "Let's ship it.")
    }
}
