import AppKit
import KibitzCore
import SwiftUI

/// A floating panel that never takes focus.
///
/// `canBecomeKey` stays false, which is the whole point: the panel must not
/// interrupt typing. The cost is that it cannot receive key events, so applying
/// a correction is done by pressing the hotkey again or clicking Apply, rather
/// than by Return. Capturing Return without stealing focus would need a
/// CGEventTap that consumes the keystroke, which is not worth it in v1.
@MainActor
final class PopupController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Long enough to read a correction and an explanation in a second language,
    /// and decide. Eight seconds was not: it vanished mid-read.
    private let autoDismiss: Duration = .seconds(25)

    func show(
        verdict: Verdict,
        original: String,
        at caretRect: CGRect?,
        hotkeyLabel: String,
        onApply: @escaping () -> Void
    ) {
        hide()

        let view = PopupView(
            verdict: verdict,
            original: original,
            hotkeyLabel: hotkeyLabel,
            onApply: onApply
        )
        let hosting = NSHostingView(rootView: view)
        hosting.layout()
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.setFrameTopLeftPoint(origin(for: size, caretRect: caretRect))
        panel.orderFrontRegardless()

        self.panel = panel
        let timeout = autoDismiss
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Called when the panel goes away for any reason, so the caller can drop
    /// the correction it was holding.
    var onHide: (() -> Void)?

    func hide() {
        let wasVisible = panel != nil
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
        if wasVisible { onHide?() }
    }

    var isVisible: Bool { panel != nil }

    /// Sits just below the caret when the app reports one, otherwise near the
    /// pointer. Both are clamped so the panel never lands off screen.
    private func origin(for size: NSSize, caretRect: CGRect?) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var point: NSPoint

        if let caretRect, caretRect != .zero {
            // AX reports screen coordinates with a top-left origin; AppKit wants
            // bottom-left, so the y axis has to be flipped.
            let flippedY = (NSScreen.screens.first?.frame.height ?? 0) - caretRect.maxY
            point = NSPoint(x: caretRect.minX, y: flippedY - 8)
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x, y: mouse.y - 12)
        }

        point.x = min(max(point.x, screen.minX + 8), screen.maxX - size.width - 8)
        point.y = min(max(point.y, screen.minY + size.height + 8), screen.maxY - 8)
        return point
    }
}
