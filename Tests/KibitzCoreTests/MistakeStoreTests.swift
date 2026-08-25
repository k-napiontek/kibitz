import Foundation
import Testing
@testable import KibitzCore

@Suite("MistakeStore")
struct MistakeStoreTests {

    /// A throwaway database per test, so these never touch the real log.
    private func scratch() -> URL {
        URL.temporaryDirectory
            .appending(path: "kibitz-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "mistakes.sqlite")
    }

    private func clean(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func verdict(
        _ outcome: Verdict.Outcome = .error,
        category: KibitzCore.Category = .tense,
        severity: Severity = .high,
        corrected: String = "I have worked here since 2020.",
        whyL1: String = "'since 2020' wymaga present perfect."
    ) -> Verdict {
        Verdict(
            outcome: outcome, category: category, severity: severity,
            corrected: corrected, whyL1: whyL1
        )
    }

    /// The privacy promise is about bytes on disk, not about a query coming back
    /// empty, so this reads every file the store touched rather than trusting
    /// the schema. WAL means the row could be in the sidecar, not the database.
    private func anyFileContains(_ needle: String, beside url: URL) throws -> Bool {
        let directory = url.deletingLastPathComponent()
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let data = try Data(contentsOf: directory.appending(path: name))
            if data.range(of: Data(needle.utf8)) != nil { return true }
        }
        return false
    }

    private let noon = Date(timeIntervalSince1970: 1_756_108_800)

    private func week(around date: Date) -> (since: Date, now: Date) {
        (date.addingTimeInterval(-7 * 24 * 3600), date.addingTimeInterval(60))
    }

    @Test("records a mistake and reads it back whole")
    func recordsAMistake() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)

        try await store.record(
            verdict(),
            original: "I work here since 2020.",
            app: "com.tinyspeck.slackmacgap",
            at: noon
        )

        let window = week(around: noon)
        let mistakes = try await store.mistakes(since: window.since, now: window.now)
        #expect(mistakes.count == 1)
        let only = try #require(mistakes.first)
        #expect(only.at == noon)
        #expect(only.category == .tense)
        #expect(only.severity == .high)
        #expect(only.original == "I work here since 2020.")
        #expect(only.corrected == "I have worked here since 2020.")
        #expect(only.whyL1 == "'since 2020' wymaga present perfect.")
        #expect(only.app == "com.tinyspeck.slackmacgap")
        #expect(only.exported == false)
    }

    @Test("a correct sentence is counted but its text is never stored")
    func correctSentencesAreCountedNotKept() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let sentence = "I have worked here since 2020."

        try await store.record(
            verdict(.ok, category: .noIssue, corrected: "", whyL1: ""),
            original: sentence, app: nil, at: noon
        )

        let window = week(around: noon)
        #expect(try await store.mistakes(since: window.since, now: window.now).isEmpty)
        #expect(try await store.counts(since: window.since, now: window.now).checked == 1)
        #expect(try anyFileContains(sentence, beside: url) == false)
    }

    @Test("a muted category still reaches the log")
    func mutedCategoriesAreStillRecorded() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let slip = verdict(category: .spelling, severity: .low, corrected: "I receive it.", whyL1: "Literowka.")

        // Pins the contract VerdictFilter states: muted means "does not interrupt",
        // never "is not recorded", or the digest goes blind to whole categories.
        #expect(VerdictFilter(config: .default).apply(slip) == .logOnly(.categoryMuted))
        try await store.record(slip, original: "I recieve it.", app: nil, at: noon)

        let window = week(around: noon)
        let mistakes = try await store.mistakes(since: window.since, now: window.now)
        #expect(mistakes.map(\.category) == [.spelling])
    }

    @Test("reads only the mistakes inside the window")
    func readsOnlyTheWindow() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let day = 24.0 * 3600

        for age in [10.0, 3.0, 1.0] {
            try await store.record(
                verdict(corrected: "aged \(age)"),
                original: "sentence \(age)", app: nil, at: noon.addingTimeInterval(-age * day)
            )
        }

        let window = week(around: noon)
        let mistakes = try await store.mistakes(since: window.since, now: window.now)
        #expect(mistakes.map(\.original) == ["sentence 1.0", "sentence 3.0"])
    }

    @Test("counts every check in the window, correct ones included")
    func countsEveryCheck() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)

        for index in 0..<2 {
            try await store.record(verdict(), original: "wrong \(index)", app: nil, at: noon)
        }
        for index in 0..<3 {
            try await store.record(
                verdict(.ok, category: .noIssue, corrected: "", whyL1: ""),
                original: "right \(index)", app: nil, at: noon
            )
        }

        let window = week(around: noon)
        let counts = try await store.counts(since: window.since, now: window.now)
        #expect(counts.checked == 5)
        #expect(counts.withMistake == 2)
        #expect(try await store.mistakes(since: window.since, now: window.now).count == 2)
    }

    @Test("both halves of the review header are counted over the same days")
    func theHeaderNumbersAgree() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let window = week(around: noon)

        // Deliberately just outside the second-granular window but inside the
        // same calendar day as its start. Counting the checks by day and the
        // mistakes by second is how a review reports 15 mistakes in 12 sentences.
        let edge = window.since.addingTimeInterval(-60)
        try await store.record(verdict(), original: "edge case", app: nil, at: edge)

        let counts = try await store.counts(since: window.since, now: window.now)
        #expect(counts.checked == counts.withMistake)
    }

    @Test("marks the selected rows exported and leaves the rest alone")
    func marksOnlyTheSelectedRows() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        for index in 0..<3 {
            try await store.record(verdict(), original: "sentence \(index)", app: nil, at: noon)
        }

        let window = week(around: noon)
        let before = try await store.mistakes(since: window.since, now: window.now)
        try await store.markExported([before[0].id, before[2].id])

        let after = try await store.mistakes(since: window.since, now: window.now)
        #expect(after.map(\.exported) == [true, false, true])
        // Exported is a mark, not a deletion: the row stays readable afterwards.
        #expect(after.map(\.original) == before.map(\.original))
    }

    @Test("an app that reports no bundle id round-trips as nil")
    func missingBundleIDRoundTrips() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)

        try await store.record(verdict(), original: "I work here since 2020.", app: nil, at: noon)

        let window = week(around: noon)
        let only = try #require(try await store.mistakes(since: window.since, now: window.now).first)
        #expect(only.app == nil)
    }

    @Test("a sentence containing a quote and a newline survives the round trip")
    func awkwardTextSurvives() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let awkward = "He said \"I work here\"\nsince 2020.\tReally."

        try await store.record(verdict(), original: awkward, app: nil, at: noon)

        let window = week(around: noon)
        let only = try #require(try await store.mistakes(since: window.since, now: window.now).first)
        #expect(only.original == awkward)
    }

    @Test("reopening an existing database keeps the rows")
    func reopeningKeepsTheRows() async throws {
        let url = scratch()
        defer { clean(url) }
        let window = week(around: noon)

        let first = try MistakeStore(url: url)
        try await first.record(verdict(), original: "I work here since 2020.", app: nil, at: noon)

        let second = try MistakeStore(url: url)
        #expect(try await second.mistakes(since: window.since, now: window.now).count == 1)
        #expect(try await second.counts(since: window.since, now: window.now).checked == 1)
    }

    @Test("deleting the log leaves a working store, not a trap")
    func deletingLeavesAWorkingStore() async throws {
        let url = scratch()
        defer { clean(url) }
        let store = try MistakeStore(url: url)
        let window = week(around: noon)
        try await store.record(verdict(), original: "I work here since 2020.", app: nil, at: noon)

        try await store.deleteEverything()

        #expect(try await store.mistakes(since: window.since, now: window.now).isEmpty)
        #expect(try await store.counts(since: window.since, now: window.now).checked == 0)

        try await store.record(verdict(), original: "I have 20 years.", app: nil, at: noon)
        #expect(try await store.mistakes(since: window.since, now: window.now).count == 1)
    }

    @Test("the log lives beside the diagnostics, where the README says it does")
    func defaultPathIsUnderApplicationSupport() {
        let path = MistakeStore.defaultURL.path
        #expect(path.hasSuffix("/Application Support/kibitz/mistakes.sqlite"))
    }

    @Test("an unwritable path throws a named error rather than crashing")
    func unwritablePathThrows() {
        // /dev/null is a file, so no directory can be created underneath it.
        let url = URL(filePath: "/dev/null/kibitz/mistakes.sqlite")
        #expect(throws: MistakeStoreError.self) { try MistakeStore(url: url) }
    }
}
