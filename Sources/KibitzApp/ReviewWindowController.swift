import AppKit
import KibitzCore
import SwiftUI

/// The app's only real window.
///
/// Deliberately the opposite of `PopupController`'s panel. That one must never
/// take focus, because it appears while you are typing. This one has checkboxes
/// and a save panel, so it has to.
@MainActor
final class ReviewWindowController {

    private var window: NSWindow?
    private var model: ReviewModel?

    func show(store: MistakeStore?, settings: ReviewSettings) {
        // A fresh model every time, so reopening a month later reviews that
        // month rather than replaying the window the first open worked out.
        let model = ReviewModel(store: store, settings: settings)
        self.model = model

        // A second open reuses the window rather than stacking another copy of
        // the same week on top of it.
        if let window {
            window.contentViewController = NSHostingController(rootView: ReviewView(model: model))
            activate(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "kibitz review"
        window.contentViewController = NSHostingController(rootView: ReviewView(model: model))
        window.setContentSize(NSSize(width: 620, height: 520))
        window.center()
        // AppKit's old ownership rule deallocates a window when it closes, which
        // leaves this controller holding a dead reference and crashes on reopen.
        window.isReleasedWhenClosed = false
        self.window = window

        activate(window)
    }

    /// An `.accessory` app has no dock icon and is never the active app, so
    /// without the activate the window opens behind whatever you were typing in
    /// and reads as nothing having happened.
    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
