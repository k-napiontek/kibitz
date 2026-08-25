import Foundation
import Testing
@testable import KibitzCore

@Suite("ReviewSchedule")
struct ReviewScheduleTests {

    private let now = Date(timeIntervalSince1970: 1_756_108_800)
    private let day: TimeInterval = 24 * 3600

    @Test("the first launch sets a baseline instead of reviewing an empty week")
    func firstLaunchSetsABaseline() {
        #expect(ReviewSchedule.decide(lastReview: nil, now: now) == .setBaseline)
    }

    @Test("six days is not due yet")
    func sixDaysIsNotDue() {
        #expect(ReviewSchedule.decide(lastReview: now.addingTimeInterval(-6 * day), now: now) == .notYet)
    }

    @Test("a review is due seven days after the last one")
    func dueOnTheSeventhDay() {
        #expect(ReviewSchedule.decide(lastReview: now.addingTimeInterval(-7 * day), now: now) == .due)
    }

    @Test("a machine asleep for three weeks finds one review due, not three")
    func sleepDoesNotQueueUpReviews() {
        // Nothing counts down, so there is no backlog to work off. The answer is
        // recomputed from the stored date and the wall clock every time.
        #expect(ReviewSchedule.decide(lastReview: now.addingTimeInterval(-21 * day), now: now) == .due)
    }

    @Test("a stored date in the future does not strand the review forever")
    func aFutureStampIsRebased() {
        // A restored backup or a clock change. Treating it as a baseline rewrites
        // it with a sane value; leaving it alone freezes reviews until the clock
        // catches up.
        #expect(ReviewSchedule.decide(lastReview: now.addingTimeInterval(day), now: now) == .setBaseline)
    }

    @Test("the window covers the last seven days")
    func windowIsAWeek() {
        #expect(ReviewSchedule.windowStart(lastReview: now.addingTimeInterval(-7 * day), now: now)
                == now.addingTimeInterval(-7 * day))
    }

    @Test("a month away still shows the whole month, not the last week of it")
    func windowStretchesBackToTheLastReview() {
        // Coming back from holiday should not silently drop three weeks of
        // mistakes, which are exactly the ones worth seeing.
        let lastReview = now.addingTimeInterval(-30 * day)

        #expect(ReviewSchedule.windowStart(lastReview: lastReview, now: now) == lastReview)
    }

    @Test("with no review ever recorded the window is still a week")
    func windowWithoutAStamp() {
        #expect(ReviewSchedule.windowStart(lastReview: nil, now: now) == now.addingTimeInterval(-7 * day))
    }
}

@Suite("ReviewSettings")
struct ReviewSettingsTests {

    /// A throwaway domain per test, so these never touch the real preferences.
    private func scratch() -> (ReviewSettings, UserDefaults, String) {
        let name = "kibitz.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ReviewSettings(defaults: defaults), defaults, name)
    }

    @Test("starts with no review ever recorded")
    func startsUnreviewed() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(settings.lastReview == nil)
    }

    @Test("remembers when the last review was")
    func persistsTheDate() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        let stamp = Date(timeIntervalSince1970: 1_756_108_800)

        settings.lastReview = stamp

        #expect(ReviewSettings(defaults: defaults).lastReview == stamp)
    }

    @Test("an unreadable stored value leaves a working app, not a trap")
    func fallsBackOnGarbage() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("last tuesday", forKey: ReviewSettings.lastReviewKey)

        #expect(settings.lastReview == nil)
    }

    @Test("the stamp is a number, so a due review can be forced from the terminal")
    func storedAsANumber() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        settings.lastReview = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(defaults.double(forKey: ReviewSettings.lastReviewKey) == 1_700_000_000)
    }
}
