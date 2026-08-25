import Foundation
import Testing
@testable import KibitzCore

@MainActor
@Suite("AccessibilityActivator")
struct AccessibilityActivatorTests {

    /// Records what would have been written, so the logic is testable without a
    /// second application running.
    private final class Recorder {
        struct Call {
            let pid: pid_t
            let attribute: String
        }
        var calls: [Call] = []
    }

    private func activator(_ recorder: Recorder) -> AccessibilityActivator {
        AccessibilityActivator { pid, attribute in
            recorder.calls.append(Recorder.Call(pid: pid, attribute: attribute))
        }
    }

    @Test("asks an app to expose its tree once, not on every keystroke")
    func nudgesOncePerApp() {
        let recorder = Recorder()
        let activator = activator(recorder)

        #expect(activator.activate(pid: 42))
        #expect(activator.activate(pid: 42) == false)
        #expect(activator.activate(pid: 42) == false)

        #expect(recorder.calls.allSatisfy { $0.pid == 42 })
        #expect(recorder.calls.count == AccessibilityActivator.attributes.count)
    }

    @Test("sets both families' attributes, because one app cannot be both")
    func setsBothAttributes() {
        let recorder = Recorder()

        activator(recorder).activate(pid: 7)

        // Electron invented AXManualAccessibility; Chromium and Firefox watch
        // AXEnhancedUserInterface, which is the one Chrome was missing.
        #expect(recorder.calls.map(\.attribute).contains("AXManualAccessibility"))
        #expect(recorder.calls.map(\.attribute).contains("AXEnhancedUserInterface"))
    }

    @Test("a different app gets its own nudge")
    func nudgesEachAppSeparately() {
        let recorder = Recorder()
        let activator = activator(recorder)

        #expect(activator.activate(pid: 1))
        #expect(activator.activate(pid: 2))

        #expect(Set(recorder.calls.map(\.pid)) == [1, 2])
    }

    @Test("an app that was never nudged is not remembered as nudged")
    func forgetsNothingItDidNotDo() {
        let recorder = Recorder()
        let activator = activator(recorder)

        #expect(activator.hasActivated(pid: 99) == false)
        activator.activate(pid: 99)
        #expect(activator.hasActivated(pid: 99))
    }
}
