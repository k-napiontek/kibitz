import AppKit
import ApplicationServices
import KibitzCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.knapiontek.kibitz", category: "app")
    private let hotkeys = HotkeyManager()
    private let reader = FocusedTextReader()
    private let corrector = Corrector()
    private let popup = PopupController()
    private let filter = VerdictFilter(config: .default)

    private var statusItem: NSStatusItem?
    private var provider: (any ModelProvider)?
    private var state: State = .idle { didSet { refreshStatusItem() } }

    /// Set while a correction is on screen, so pressing the hotkey again applies
    /// it rather than starting a second check.
    private var pending: PendingCorrection?

    private struct PendingCorrection {
        let verdict: Verdict
        let original: String
        let target: CheckTarget
    }

    private enum State {
        case idle, checking, error(String)
    }

    private let hotkeyLabel = "\u{2318}\u{21E7}E"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpProvider()
        hotkeys.register { [weak self] in
            Task { @MainActor in self?.hotkeyPressed() }
        }
        requestAccessibilityIfNeeded()
    }

    // MARK: - Wiring

    private func setUpProvider() {
        do {
            let prompt = try BundledPrompt.renderedSystemPrompt(for: .polish)
            provider = ClaudeCodeProvider(systemPrompt: prompt)
        } catch {
            state = .error("Could not load the coaching prompt")
            logger.error("prompt load failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func hotkeyPressed() {
        // Second press applies what is already on screen.
        if let pending, popup.isVisible {
            apply(pending)
            return
        }
        guard case .checking = state else {
            Task { await check() }
            return
        }
    }

    private func check() async {
        guard let provider else { return }
        state = .checking
        popup.hide()

        let focused = reader.read()
        let target = CheckTargetResolver.resolve(focused)

        let sentence: String
        let previous: String?
        switch target {
        case .selection(let text):
            sentence = text
            previous = nil
        case .sentence(let text, let context):
            sentence = text
            previous = context
        case .nothing(let reason):
            state = .idle
            logger.info("nothing to check: \(reason.rawValue, privacy: .public)")
            return
        }

        do {
            let verdict = try await provider.check(sentence: sentence, previous: previous)
            state = .idle

            guard filter.apply(verdict) == .show else {
                logger.info("suppressed, verdict \(verdict.outcome.rawValue, privacy: .public)")
                return
            }
            pending = PendingCorrection(verdict: verdict, original: sentence, target: target)
            popup.show(
                verdict: verdict,
                original: sentence,
                at: reader.caretRect(),
                hotkeyLabel: hotkeyLabel
            ) { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.apply(pending)
            }
        } catch {
            state = .error(String(describing: error))
            logger.error("check failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(_ pending: PendingCorrection) {
        popup.hide()
        self.pending = nil
        let outcome = corrector.apply(
            correction: pending.verdict.corrected,
            replacing: pending.original,
            target: pending.target
        )
        if outcome == .failed {
            state = .error("Could not write the correction back")
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "text.bubble", accessibilityDescription: "kibitz"
        )
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Check now  \(hotkeyLabel)",
            action: #selector(checkNow), keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Accessibility permission...",
            action: #selector(openAccessibilitySettings), keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit kibitz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "kibitz")
            button.toolTip = "kibitz"
        case .checking:
            button.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "checking")
            button.toolTip = "Checking..."
        case .error(let message):
            button.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: "error")
            button.toolTip = message
        }
    }

    @objc private func checkNow() { Task { await check() } }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func requestAccessibilityIfNeeded() {
        // kAXTrustedCheckOptionPrompt is a mutable global, which Swift 6 will not
        // let us touch. Its documented value is this literal.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            state = .error("kibitz needs the Accessibility permission to read what you type")
        }
    }
}
