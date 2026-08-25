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
    private let selectionReader = SelectionReader()
    private let popup = PopupController()
    private let filter = VerdictFilter(config: .default)
    private let settings = BackendSettings()
    private let keys = APIKeyStore()
    /// Optional because a database that will not open must cost you the log, not
    /// the correction you pressed the hotkey for.
    private var mistakes: MistakeStore?
    private let review = ReviewWindowController()
    private let reviewSettings = ReviewSettings()

    private var statusItem: NSStatusItem?
    /// Shown in the menu. The unified log is not readable everywhere, so the app
    /// has to be able to explain itself without it.
    private var lastEventItem: NSMenuItem?
    /// Held so the checkmarks and the enabled state can follow the settings
    /// without rebuilding the menu.
    private var backendItems: [Backend: NSMenuItem] = [:]
    private var modelItems: [DeepSeekModel: NSMenuItem] = [:]
    private var modelMenuItem: NSMenuItem?
    private var removeKeyItem: NSMenuItem?
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
    /// Held so it can be cancelled, and so the loop is not started twice.
    private var reviewTicker: Task<Void, Never>?

    private struct PendingCorrection {
        let verdict: Verdict
        let original: String
        let target: CheckTarget
    }

    private enum State {
        case idle, checking, error(String)
    }

    private static let hotkeyLabel = "\u{2318}\u{21E7}E"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Notice level, so `log show` keeps it. Diagnosing "nothing happened"
        // without a record of whether the hotkey even fired is guesswork.
        logger.notice("kibitz launched")
        DiagnosticLog.write("=== launched ===")
        openMistakeLog()
        PopupController.clearLegacyPinnedPosition()
        setUpStatusItem()
        setUpProvider()
        // A correction is only applicable while it is on screen.
        popup.onHide = { [weak self] in self?.pending = nil }
        hotkeys.register { [weak self] in
            Task { @MainActor in self?.hotkeyPressed() }
        }
        requestAccessibilityIfNeeded()
        startReviewTicker()
    }

    // MARK: - Wiring

    private func openMistakeLog() {
        do {
            mistakes = try MistakeStore(url: MistakeStore.defaultURL)
            DiagnosticLog.write("log: opened \(MistakeStore.defaultURL.path)")
        } catch {
            mistakes = nil
            DiagnosticLog.write("log: FAILED to open, \(error)")
        }
    }

    /// Every verdict, not only the ones that reach the popup. `VerdictFilter`
    /// decides what interrupts the writer and nothing else, so the muted
    /// categories and the correct sentences have to be recorded from here,
    /// before its guard.
    ///
    /// Detached and swallowed, because a slow or broken disk must never sit
    /// between the model answering and the popup appearing.
    private func record(_ verdict: Verdict, original: String, app: String) {
        guard let mistakes else { return }
        Task.detached(priority: .utility) {
            do {
                try await mistakes.record(
                    verdict, original: original, app: app.isEmpty ? nil : app, at: Date()
                )
            } catch {
                DiagnosticLog.write("log: FAILED to record, \(error)")
            }
        }
    }

    /// Re-run whenever the backend, the model or the key changes, so the next
    /// hotkey press uses what the menu says.
    private func setUpProvider() {
        do {
            let resolved = try ProviderResolver.make(settings: settings, keys: keys)
            provider = resolved
            providerError = nil
            if case .error = state { state = .idle }
            DiagnosticLog.write("provider: \(resolved.displayName)")
        } catch {
            provider = nil
            providerError = Self.explain(error)
            state = .error(providerError ?? "")
            lastEvent = providerError ?? ""
            logger.error("provider setup failed: \(String(describing: error), privacy: .public)")
            DiagnosticLog.write("provider: FAILED \(error)")
        }
        refreshBackendMenu()
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
        if provider == nil {
            // A missing provider is often transient - a Keychain prompt that went
            // unanswered, most of all - so pressing the hotkey again has to be a
            // real second chance rather than a replay of the same error.
            DiagnosticLog.write("check: no provider, resolving again")
            setUpProvider()
        }
        guard let provider else {
            // Returning silently here is what made this look like a hang: the menu
            // sat on "Checking..." while nothing was running.
            DiagnosticLog.write("check: NO PROVIDER, \(providerError ?? "unknown")")
            lastEvent = providerError ?? "No backend is configured"
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
        // Captured now, not after the model answers. Resolving the anchor at the
        // call site of popup.show meant a five second round trip sat between the
        // hotkey and the measurement, so a click during the check moved the popup
        // to whatever was focused by then. The popup belongs to the sentence that
        // was checked.
        let snapshot = await reader.capture()
        let focused = snapshot.text
        DiagnosticLog.write("""
            check: read app=\(focused.appBundleID) secure=\(focused.isSecureField)             valueChars=\(focused.value?.count ?? -1) selChars=\(focused.selectedText?.count ?? -1)             caret=\(focused.caretOffset.map(String.init) ?? "nil") anchor=\(snapshot.anchor.source.rawValue)
            """)
        var target = CheckTargetResolver.resolve(focused)

        // Last resort, for apps that expose no tree at all even after being
        // asked. Deliberately gated on `noReadableText`: a secure field resolves
        // to its own case and never reaches the clipboard.
        if case .nothing(.noReadableText) = target, let copied = selectionReader.copySelection() {
            DiagnosticLog.write("check: read \(copied.count) chars from the selection instead")
            target = .selection(copied)
        }

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

            record(verdict, original: sentence, app: focused.appBundleID)

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
                at: snapshot.anchor,
                hotkeyLabel: Self.hotkeyLabel
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
        // Without this, AppKit enables any item whose target responds to its
        // action, and every `isEnabled` set below is quietly ignored.
        menu.autoenablesItems = false
        let event = NSMenuItem(title: lastEvent, action: nil, keyEquivalent: "")
        event.isEnabled = false
        menu.addItem(event)
        lastEventItem = event
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Check now  \(Self.hotkeyLabel)",
            action: #selector(checkNow), keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Review mistakes...",
            action: #selector(openReview), keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(makeBackendMenuItem())
        menu.addItem(makeModelMenuItem())
        menu.addItem(
            withTitle: "Set DeepSeek API key...",
            action: #selector(setAPIKey), keyEquivalent: ""
        ).target = self
        let remove = NSMenuItem(
            title: "Remove DeepSeek API key",
            action: #selector(removeAPIKey), keyEquivalent: ""
        )
        remove.target = self
        menu.addItem(remove)
        removeKeyItem = remove
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Accessibility permission...",
            action: #selector(openAccessibilitySettings), keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit kibitz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        refreshBackendMenu()
    }

    private func makeBackendMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for backend in Backend.allCases {
            let entry = NSMenuItem(
                title: backend.menuTitle, action: #selector(selectBackend), keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = backend.rawValue
            submenu.addItem(entry)
            backendItems[backend] = entry
        }
        let item = NSMenuItem(title: "Backend", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func makeModelMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for model in DeepSeekModel.allCases {
            let entry = NSMenuItem(
                title: model.menuTitle, action: #selector(selectModel), keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = model.rawValue
            submenu.addItem(entry)
            modelItems[model] = entry
        }
        let item = NSMenuItem(title: "DeepSeek model", action: nil, keyEquivalent: "")
        item.submenu = submenu
        modelMenuItem = item
        return item
    }

    /// Checkmarks follow the stored settings, and the model submenu is greyed
    /// out on the subscription backend rather than offering a choice that
    /// changes nothing.
    private func refreshBackendMenu() {
        let backend = settings.backend
        for (candidate, entry) in backendItems {
            entry.state = candidate == backend ? .on : .off
        }
        let model = settings.deepSeekModel
        for (candidate, entry) in modelItems {
            entry.state = candidate == model ? .on : .off
        }
        modelMenuItem?.isEnabled = backend == .deepseek
        modelMenuItem?.submenu?.items.forEach { $0.isEnabled = backend == .deepseek }
        removeKeyItem?.isEnabled = keys.exists()
    }

    @objc private func selectBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let backend = Backend(rawValue: raw)
        else { return }
        settings.backend = backend
        setUpProvider()
        if let provider { lastEvent = "Backend: \(provider.displayName)" }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let model = DeepSeekModel(rawValue: raw)
        else { return }
        settings.deepSeekModel = model
        setUpProvider()
        if let provider { lastEvent = "Model: \(provider.displayName)" }
    }

    /// A secure field in an alert, because the alternative is a settings window
    /// this app does not have yet and does not otherwise need.
    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "DeepSeek API key"
        alert.informativeText = "Stored in your login Keychain, never in the app bundle or a preferences file. Create a key at platform.deepseek.com."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-..."
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        do {
            try keys.save(key)
            // Deliberately does not switch backend: where sentences go stays an
            // explicit choice, so storing a key never silently reroutes them.
            lastEvent = settings.backend == .deepseek
                ? "Key saved"
                : "Key saved. Pick DeepSeek API under Backend to use it."
            setUpProvider()
        } catch {
            lastEvent = "Could not save the key to the Keychain: \(error)"
            DiagnosticLog.write("keychain: save FAILED \(error)")
        }
    }

    @objc private func removeAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Remove the DeepSeek API key?"
        alert.informativeText = "kibitz will go back to the Claude subscription backend."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try keys.delete()
            // Leaving DeepSeek selected with no key would strand the app in an
            // error state it cannot check its way out of.
            if settings.backend == .deepseek { settings.backend = .subscription }
            lastEvent = "Key removed, back on the Claude subscription"
            setUpProvider()
        } catch {
            lastEvent = "Could not remove the key: \(error)"
            DiagnosticLog.write("keychain: delete FAILED \(error)")
        }
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

    // MARK: - The weekly review

    /// Re-evaluates rather than counting down.
    ///
    /// A date comparison against the stored stamp means a laptop that spent the
    /// week asleep finds the review due on the next tick instead of having
    /// missed its slot, and it means the tick interval only bounds how late the
    /// window can be, never whether it appears at all. Waking the lid checks
    /// immediately so Monday morning does not wait out the rest of an hour.
    private func startReviewTicker() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showReviewIfDue() }
        }
        reviewTicker = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.showReviewIfDue() }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func showReviewIfDue() {
        switch ReviewSchedule.decide(lastReview: reviewSettings.lastReview, now: Date()) {
        case .notYet:
            return
        case .setBaseline:
            // First launch, or a stamp that cannot be true. Start the clock and
            // stay quiet: a review window on day one has nothing in it.
            reviewSettings.lastReview = Date()
            DiagnosticLog.write("review: baseline set")
        case .due:
            // Stealing focus mid-check is exactly the interruption this app
            // exists not to be. The next tick catches it.
            guard !checkInFlight, !popup.isVisible else {
                DiagnosticLog.write("review: due, deferred until the check finishes")
                return
            }
            Task { await openReviewIfWorthIt() }
        }
    }

    /// A due review with nothing in it moves the stamp and stays quiet. Opening
    /// a window that says "nothing to review" is worse than not opening one, and
    /// leaving the stamp alone would make the check fire every hour forever.
    private func openReviewIfWorthIt() async {
        guard let mistakes else {
            reviewSettings.lastReview = Date()
            return
        }
        let now = Date()
        let since = ReviewSchedule.windowStart(lastReview: reviewSettings.lastReview, now: now)
        let digest = try? await mistakes.review(since: since, now: now)
        guard let digest, !digest.isEmpty else {
            reviewSettings.lastReview = now
            DiagnosticLog.write("review: due but empty, stayed quiet")
            return
        }
        DiagnosticLog.write("review: opening, \(digest.selectableIDs.count) cards on offer")
        openReview()
    }

    @objc private func openReview() {
        review.show(store: mistakes, settings: reviewSettings)
        lastEvent = "Opened the review"
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
        if case ProviderResolutionError.noAPIKey = error {
            return "No DeepSeek key. Set one from the menu, or switch back to the subscription."
        }
        if case KeychainError.userCancelled = error {
            // Expected after every rebuild: the Keychain ACL is bound to the
            // exact binary, so a fresh build is a stranger to its own key.
            return "Keychain access was declined. Press \(hotkeyLabel) again and click Always Allow."
        }
        if let error = error as? DeepSeekError {
            switch error {
            case .unauthorized:
                return "DeepSeek rejected the key. Set it again from the menu."
            case .insufficientBalance:
                return "DeepSeek balance is empty. Top it up at platform.deepseek.com."
            case .rateLimited:
                return "DeepSeek is rate limiting. Try again in a moment."
            case .serverError(let status, let message):
                return "DeepSeek returned \(status): \(message.prefix(80))"
            case .emptyContent:
                return "DeepSeek returned an empty reply twice. Try again."
            case .truncated:
                return "DeepSeek hit its output limit before finishing the answer."
            case .replyWasNotJSON(let reply):
                return "DeepSeek did not reply with JSON: \(reply.prefix(60))"
            case .timedOut:
                return "DeepSeek did not answer within 15s."
            case .transport(let detail):
                return "Could not reach DeepSeek: \(detail.prefix(80))"
            }
        }
        if error is PromptError {
            return "Coaching prompt failed to load: \(error)"
        }
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
        if case SubprocessError.nonZeroExit(let code, let stderr, _) = error {
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
