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
/// macOS constrains ordinary windows so they cannot be dragged under the menu
/// bar. For a small floating panel that is just an invisible wall, so it is
/// lifted here.
private final class FreelyMovablePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class PopupController {

    /// Removes the position saved by an earlier build.
    ///
    /// That build remembered wherever the popup was dragged and reused it
    /// forever, which meant one accidental drag stopped the popup following the
    /// text at all. The feature is gone; this clears its leftovers.
    static func clearLegacyPinnedPosition() {
        UserDefaults.standard.removeObject(forKey: "popup.pinnedOrigin")
    }

    /// Frame origin when the current drag started. Dragging moves only the panel
    /// on screen: the next popup is placed under the text again.
    private var dragStartOrigin: NSPoint?

    func dragChanged(translation: CGSize) {
        guard let panel else { return }
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            // Do not let it vanish out from under the pointer mid-drag.
            dismissTask?.cancel()
        }
        guard let start = dragStartOrigin else { return }
        // SwiftUI measures y downward, AppKit upward.
        panel.setFrameOrigin(
            NSPoint(x: start.x + translation.width, y: start.y - translation.height)
        )
    }

    func dragEnded() { dragStartOrigin = nil }
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Long enough to read a correction and an explanation in a second language,
    /// and decide. Eight seconds was not: it vanished mid-read.
    private let autoDismiss: Duration = .seconds(25)

    func show(
        verdict: Verdict,
        original: String,
        at anchor: CGRect?,
        hotkeyLabel: String,
        onApply: @escaping () -> Void
    ) {
        hide()

        let view = PopupView(
            verdict: verdict,
            original: original,
            hotkeyLabel: hotkeyLabel,
            onApply: onApply,
            onDismiss: { [weak self] in self?.hide() },
            onDragChanged: { [weak self] translation in self?.dragChanged(translation: translation) },
            onDragEnded: { [weak self] in self?.dragEnded() }
        )
        // NSHostingController.sizeThatFits is the API meant for this: it asks
        // SwiftUI how tall the content wants to be at a given width. NSHostingView
        // either grew the window to 1271pt on its own, or reported zero once that
        // growth was disabled. sizingOptions = [] keeps it from resizing the panel
        // after the fact.
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        let size = controller.sizeThatFits(
            in: NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        )

        let panel = FreelyMovablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        // Drag it anywhere: the anchor is a good guess, not always the right place.
        panel.isMovableByWindowBackground = true
        panel.setFrameTopLeftPoint(origin(for: size, anchor: anchor))
        panel.orderFrontRegardless()
        // Log where it actually is. Logging the computed value while placing the
        // panel somewhere else is what hid the pinning bug.
        panel.setContentSize(size)
        DiagnosticLog.write("popup: placed at \(panel.frame.debugDescription)")
        // Log again once SwiftUI has settled. Logging only at creation time is
        // what hid the window growing after the fact.
        let panelRef = panel
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            DiagnosticLog.write("popup: settled at \(panelRef.frame.debugDescription)")
        }


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
        dragStartOrigin = nil
        panel?.orderOut(nil)
        panel = nil
        if wasVisible { onHide?() }
    }

    var isVisible: Bool { panel != nil }

    /// Sits just below the text it is correcting.
    ///
    /// Accessibility reports screen coordinates with the origin at the top left
    /// of the primary display; AppKit measures from the bottom left, so the y
    /// axis has to be flipped against that same primary screen.
    private func origin(for size: NSSize, anchor: CGRect?) -> NSPoint {
        // Enough to clear the text and its cursor. At 6 the panel sat directly on
        // the line it was correcting.
        let gap: CGFloat = 14
        var point: NSPoint

        if let anchor, anchor.width > 0, anchor.height > 0 {
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            point = NSPoint(x: anchor.minX, y: primaryHeight - anchor.maxY - gap)
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x, y: mouse.y - gap)
        }

        // Keep it on the screen the anchor actually lives on.
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        point.x = min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8)
        // If there is no room below, flip above the text rather than clipping.
        if point.y - size.height < visible.minY + 8, let anchor {
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            point.y = primaryHeight - anchor.minY + size.height + gap
        }
        point.y = min(max(point.y, visible.minY + size.height + 8), visible.maxY - 8)
        DiagnosticLog.write("popup: anchor=\(anchor?.debugDescription ?? "nil") computed=\(point.debugDescription)")
        return point
    }
}
