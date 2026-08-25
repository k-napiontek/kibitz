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
    /// Shown in the menu. The unified log is not readable everywhere, so the app
    /// has to be able to explain itself without it.
    private var lastEventItem: NSMenuItem?
    private var lastEvent = "No checks yet" { didSet { lastEventItem?.title = lastEvent } }
    private var provider: (any ModelProvider)?
    private var providerError: String?
    private var state: State = .idle { didSet { refreshStatusItem() } }

    /// Set while a correction is on screen, so pressing the hotkey again applies
    /// it rather than starting a second check.
    private var pending: PendingCorrection?
    /// Guards against overlapping checks. Two concurrent CLI processes competed
    /// badly enough to stretch a five second check to thirty seven.
    private var checkInFlight = false

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
        // Notice level, so `log show` keeps it. Diagnosing "nothing happened"
        // without a record of whether the hotkey even fired is guesswork.
        logger.notice("kibitz launched")
        DiagnosticLog.write("=== launched ===")
        setUpStatusItem()
        setUpProvider()
        // A correction is only applicable while it is on screen.
        popup.onHide = { [weak self] in self?.pending = nil }
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
            providerError = "Coaching prompt failed to load: \(error)"
            lastEvent = providerError ?? ""
            logger.error("prompt load failed: \(String(describing: error), privacy: .public)")
            DiagnosticLog.write("startup: prompt load FAILED \(error)")
        }
    }

    private func hotkeyPressed() {
        logger.notice("hotkey pressed")

        // Second press applies what is already on screen.
        if let pending, popup.isVisible {
            apply(pending)
            return
        }
        guard !checkInFlight else {
            lastEvent = "Already checking, one moment"
            DiagnosticLog.write("hotkey: ignored, a check is already running")
            return
        }
        lastEvent = "Checking..."
        Task { await check() }
    }

    private func check() async {
        DiagnosticLog.write("check: begin")
        checkInFlight = true
        defer { checkInFlight = false }
        guard let provider else {
            // Returning silently here is what made this look like a hang: the menu
            // sat on "Checking..." while nothing was running.
            DiagnosticLog.write("check: NO PROVIDER, prompt failed to load")
            lastEvent = providerError ?? "Coaching prompt could not be loaded"
            state = .error(lastEvent)
            return
        }
        state = .checking
        popup.hide()

        // Without this, a denied permission looks identical to an app that
        // exposes no text, and the app reports the wrong cause.
        guard AXIsProcessTrusted() else {
            DiagnosticLog.write("check: NOT TRUSTED for accessibility")
            lastEvent = "No Accessibility permission. Open the menu item below."
            state = .error("kibitz needs Accessibility permission")
            requestAccessibilityIfNeeded()
            return
        }

        DiagnosticLog.write("check: trusted=true reading focused element")
        let focused = reader.read()
        DiagnosticLog.write("""
            check: read app=\(focused.appBundleID) secure=\(focused.isSecureField)             valueChars=\(focused.value?.count ?? -1) selChars=\(focused.selectedText?.count ?? -1)             caret=\(focused.caretOffset.map(String.init) ?? "nil")
            """)
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
            DiagnosticLog.write("check: nothing to check (\(reason.rawValue))")
            state = .idle
            logger.notice("nothing to check: \(reason.rawValue, privacy: .public)")
            lastEvent = reason == .secureField
                ? "Skipped: a password field was focused"
                : "Nothing readable in that field"
            return
        }

        DiagnosticLog.write("check: calling provider, \(sentence.count) chars")
        do {
            let verdict = try await provider.check(sentence: sentence, previous: previous)
            DiagnosticLog.write("check: provider returned \(verdict.outcome.rawValue)")
            state = .idle
            // The sentence itself is private: it never reaches the system log.
            logger.notice("""
                check finished, verdict \(verdict.outcome.rawValue, privacy: .public)                 category \(verdict.category.rawValue, privacy: .public)                 sentence \(sentence, privacy: .private)
                """)

            guard filter.apply(verdict) == .show else {
                logger.notice("popup suppressed by the category filter")
                lastEvent = verdict.outcome == .ok
                    ? "That sentence looks correct"
                    : "Found \(verdict.category.rawValue), muted by your settings"
                return
            }
            lastEvent = "Showed a fix for \(verdict.category.rawValue)"
            DiagnosticLog.write("check: showing popup")
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
            lastEvent = Self.explain(error)
            DiagnosticLog.write("check: FAILED \(error)")
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
        lastEvent = outcome == .applied
            ? "Correction applied"
            : "Could not write the correction back"
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
        let event = NSMenuItem(title: lastEvent, action: nil, keyEquivalent: "")
        event.isEnabled = false
        menu.addItem(event)
        lastEventItem = event
        menu.addItem(.separator())
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

    @objc private func checkNow() {
        guard !checkInFlight else {
            lastEvent = "Already checking, one moment"
            return
        }
        lastEvent = "Checking..."
        Task { await check() }
    }

    /// Provider failures are useless as raw enum text. Name the fix instead.
    private static func explain(_ error: Error) -> String {
        if case ClaudeCodeParseError.cliReportedError(let message) = error {
            if message.localizedCaseInsensitiveContains("not logged in") {
                return "Claude CLI is not logged in for this app. Run: claude /login"
            }
            return "Claude CLI: \(message.prefix(80))"
        }
        if case SubprocessError.timedOut(let seconds, let bytes, _) = error {
            return String(
                format: "Timed out after %.0fs with %d bytes. The CLI may be stuck on a keychain prompt.",
                seconds, bytes
            )
        }
        if case SubprocessError.launchFailed = error {
            return "Could not start the claude CLI. Is it at ~/.local/bin/claude?"
        }
        if case SubprocessError.nonZeroExit(let code, let stderr) = error {
            return "claude exited \(code): \(stderr.prefix(80))"
        }
        return "Check failed: \(error)"
    }

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
