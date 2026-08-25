import Foundation
import Security
import Testing
@testable import KibitzCore

/// Touches the real login Keychain, under throwaway account names it cleans up.
/// The Keychain went untested in the first pass, and that is exactly where the
/// prompt-on-every-rebuild bug hid.
@Suite("APIKeyStore")
struct APIKeyStoreTests {

    private func scratchStore() -> APIKeyStore {
        APIKeyStore(account: "kibitz-tests-\(UUID().uuidString)")
    }

    @Test("stores a key, reads it back, and removes it")
    func roundTrips() throws {
        let store = scratchStore()
        defer { try? store.delete() }

        #expect(try store.read() == nil)
        try store.save("sk-round-trip")
        #expect(try store.read() == "sk-round-trip")
        try store.delete()
        #expect(try store.read() == nil)
    }

    @Test("replaces the stored key rather than failing on a duplicate")
    func overwritesAnExistingKey() throws {
        let store = scratchStore()
        defer { try? store.delete() }

        try store.save("sk-first")
        try store.save("sk-second")

        #expect(try store.read() == "sk-second")
    }

    @Test("trims the key, because a pasted secret usually brings whitespace")
    func trimsWhatYouPaste() throws {
        let store = scratchStore()
        defer { try? store.delete() }

        try store.save("  sk-padded\n")

        #expect(try store.read() == "sk-padded")
    }

    @Test("removing a key that was never stored is not an error")
    func deletingNothingSucceeds() throws {
        try scratchStore().delete()
    }

    @Test("existence is answered without reading the secret, so it cannot prompt")
    func checksExistenceWithoutTouchingTheSecret() throws {
        // Keychain ACLs guard the secret, not the attributes. Asking "is there a
        // key?" by fetching the key is what made a rebuilt app throw a system
        // prompt at you before you had asked it to do anything.
        let store = scratchStore()
        defer { try? store.delete() }

        #expect(store.exists() == false)
        try store.save("sk-exists")
        #expect(store.exists())
    }

    @Test("a cancelled Keychain prompt is a named condition, not a bare status code")
    func namesTheCancelledPrompt() {
        #expect(KeychainError.from(errSecUserCanceled) == .userCancelled)
        #expect(KeychainError.from(errSecItemNotFound) == .failed(errSecItemNotFound))
    }
}
