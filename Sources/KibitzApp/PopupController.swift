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
/// lifted here. `PopupPlacement` is consequently the only thing keeping the
/// panel on screen.
private final class FreelyMovablePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class PopupController {

    /// The width the content is measured at. `PopupView` caps itself at the same
    /// number, so the measured size is the size the panel actually takes, which
    /// placement now depends on.
    static let contentWidth: CGFloat = 440

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
        at anchor: TextAnchor,
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
            in: NSSize(width: Self.contentWidth, height: CGFloat.greatestFiniteMagnitude)
        )

        let layout = screenLayout()
        DiagnosticLog.write("screens: \(describe(layout))")
        guard let topLeft = PopupPlacement.topLeft(
            panelSize: size, anchor: anchor, layout: layout
        ) else {
            // No display attached: a locked screen, or every monitor asleep.
            // Placing the panel anyway would put it at the origin of nowhere.
            DiagnosticLog.write("popup: no display to place it on, skipped")
            return
        }
        DiagnosticLog.write("""
            popup: source=\(anchor.source.rawValue) ax=\(anchor.rect.debugDescription) \
            topLeft=\(topLeft.debugDescription)
            """)

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
        // Size before position. Resizing afterwards is what made the computed
        // point and the placed frame disagree.
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        // Log where it actually is. Logging the computed value while placing the
        // panel somewhere else is what hid the pinning bug.
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

    /// The only place `NSScreen` is read.
    ///
    /// Everything downstream of this is a value type, so a monitor arrangement
    /// can be reproduced in a test without plugging in a second monitor. None of
    /// the placement bugs this replaced were catchable otherwise.
    private func screenLayout() -> ScreenLayout {
        ScreenLayout(
            screens: NSScreen.screens.map {
                ScreenLayout.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
        )
    }

    /// A monitor arrangement cannot be reconstructed from a log without this.
    private func describe(_ layout: ScreenLayout) -> String {
        layout.screens.enumerated()
            .map { "\($0.offset) frame=\($0.element.frame.debugDescription) visible=\($0.element.visibleFrame.debugDescription)" }
            .joined(separator: "  ")
    }
}
