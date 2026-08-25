import AppKit
import KibitzCore
import Observation
import UniformTypeIdentifiers

/// The state behind the review window.
///
/// Everything it decides is a call into `KibitzCore`, which is where the logic
/// is tested. What lives here is the part no test can reach: a save panel, a
/// clipboard-free file write, and the reload afterwards.
@MainActor
@Observable
final class ReviewModel {

    private(set) var digest: MistakeDigest?
    /// Set when the log itself is broken. "Nothing to review" when the truth is
    /// "the log will not open" is the kind of lie that costs trust.
    private(set) var failure: String?
    private(set) var lastExport: String?
    var selected: Set<Int64> = []

    private let store: MistakeStore?
    private let settings: ReviewSettings
    /// The span this review covers, fixed on the first load and reused for
    /// every reload.
    ///
    /// Recomputing it would collapse a month-long catch-up window down to seven
    /// days the moment the stamp is written, and the rows the review had just
    /// listed would vanish out from under the export.
    ///
    /// Not observed: it is bookkeeping, and nothing on screen reads it.
    @ObservationIgnored private var window: Window?

    struct Window {
        let since: Date
        let now: Date
    }

    init(store: MistakeStore?, settings: ReviewSettings = ReviewSettings()) {
        self.store = store
        self.settings = settings
    }

    var isEmpty: Bool { digest?.isEmpty ?? true }

    func load() async {
        guard let store else {
            failure = "The mistake log could not be opened, so nothing was recorded."
            return
        }
        let span = window ?? openWindow()
        do {
            let digest = try await store.review(since: span.since, now: span.now)
            self.digest = digest
            self.failure = nil
            // Everything on the list is by definition not a card yet, so all of
            // it selected is the right default for a weekly habit.
            self.selected = Set(digest.selectableIDs)
        } catch {
            self.failure = String(describing: error)
        }
    }

    /// Reading the week counts as reviewing it, so the stamp moves here rather
    /// than at either call site. Opening the review by hand on Tuesday therefore
    /// moves the automatic one to next Tuesday, which is the honest reading of
    /// "once a week".
    private func openWindow() -> Window {
        let now = Date()
        let span = Window(since: ReviewSchedule.windowStart(lastReview: settings.lastReview, now: now), now: now)
        window = span
        settings.lastReview = now
        return span
    }

    func selectAll() { selected = Set(digest?.selectableIDs ?? []) }
    func selectNone() { selected = [] }

    func toggle(_ id: Int64) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Marks the rows exported only after the file has actually landed. A
    /// cancelled or failed save must not quietly consume the cards.
    func exportSelected() async {
        guard let store, let digest else { return }
        let chosen = digest.groups.flatMap(\.items).filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = AnkiExport.filename(for: Date())
        panel.directoryURL = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        panel.allowedContentTypes = [.plainText]
        panel.message = "Import this into Anki with File > Import, using the Basic note type."
        // An accessory app has no dock icon, so without this the panel opens
        // behind whatever you were typing in and looks like nothing happened.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(AnkiExport.tsv(for: chosen).utf8).write(to: url)
            try await store.markExported(chosen.map(\.id))
            lastExport = "Exported \(chosen.count) to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
            await load()
        } catch {
            failure = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func revealLog() {
        guard let store else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }
}
