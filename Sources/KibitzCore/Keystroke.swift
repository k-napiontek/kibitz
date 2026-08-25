import AppKit

/// Synthesizes the two clipboard shortcuts kibitz needs.
///
/// Shared so that reading a selection and writing a correction back cannot drift
/// apart in how they post events.
public enum Keystroke {

    private static let c = CGKeyCode(8)
    private static let v = CGKeyCode(9)

    public static func commandC() { sendWithCommand(c) }
    public static func commandV() { sendWithCommand(v) }

    private static func sendWithCommand(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
