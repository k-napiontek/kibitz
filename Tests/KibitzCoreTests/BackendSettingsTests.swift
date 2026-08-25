import Foundation
import Testing
@testable import KibitzCore

@Suite("BackendSettings")
struct BackendSettingsTests {

    /// A throwaway domain per test, so these never touch the real preferences.
    private func scratch() -> (BackendSettings, UserDefaults, String) {
        let name = "kibitz.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (BackendSettings(defaults: defaults), defaults, name)
    }

    @Test("starts on the subscription, the backend that needs no key")
    func defaultsToSubscription() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(settings.backend == .subscription)
        #expect(settings.deepSeekModel == .flash)
    }

    @Test("remembers the choice")
    func persistsTheChoice() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        settings.backend = .deepseek
        settings.deepSeekModel = .pro

        #expect(BackendSettings(defaults: defaults).backend == .deepseek)
        #expect(BackendSettings(defaults: defaults).deepSeekModel == .pro)
    }

    @Test("an unreadable stored value leaves a working app, not a trap")
    func fallsBackOnGarbage() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("anthropic", forKey: BackendSettings.backendKey)
        defaults.set("deepseek-chat", forKey: BackendSettings.modelKey)

        #expect(settings.backend == .subscription)
        #expect(settings.deepSeekModel == .flash)
    }

    @Test("every backend can be named in a menu")
    func backendsAreNameable() {
        for backend in Backend.allCases {
            #expect(!backend.menuTitle.isEmpty)
        }
        for model in DeepSeekModel.allCases {
            #expect(!model.menuTitle.isEmpty)
        }
    }

}
