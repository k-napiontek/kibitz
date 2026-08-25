import Foundation
import Testing
@testable import KibitzCore

@Suite("StartupSettings")
struct StartupSettingsTests {

    /// A throwaway domain per test, so these never touch the real preferences.
    private func scratch() -> (StartupSettings, UserDefaults, String) {
        let name = "kibitz.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (StartupSettings(defaults: defaults), defaults, name)
    }

    @Test("a fresh install has not been offered a login item yet")
    func startsUnoffered() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(settings.didAttemptRegistration == false)
    }

    @Test("remembers that it already registered once")
    func persistsTheAttempt() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        settings.didAttemptRegistration = true

        #expect(StartupSettings(defaults: defaults).didAttemptRegistration == true)
    }

    @Test("turning it off stays off across a relaunch")
    func neverRegistersTwice() {
        // The whole reason this flag exists. Registering on every launch would
        // silently undo the toggle every time the app started.
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(settings.shouldRegisterAtLaunch(isEnabled: false) == true)
        settings.didAttemptRegistration = true
        #expect(settings.shouldRegisterAtLaunch(isEnabled: false) == false)
    }

    @Test("an already enabled login item is left alone")
    func doesNotReregisterWhenAlreadyOn() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(settings.shouldRegisterAtLaunch(isEnabled: true) == false)
    }

    @Test("an unreadable stored value leaves a working app, not a trap")
    func fallsBackOnGarbage() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("yes please", forKey: StartupSettings.didRegisterKey)

        #expect(settings.didAttemptRegistration == false)
    }
}
