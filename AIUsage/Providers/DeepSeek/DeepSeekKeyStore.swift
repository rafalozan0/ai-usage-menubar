import Foundation

/// Stores the DeepSeek API key that the user pastes into Settings.
///
/// DeepSeek has no CLI login to reuse, so the key lives in an item that AI
/// Usage owns in the macOS Keychain.
struct DeepSeekKeyStore: Sendable {
    static let service = "AI Usage DeepSeek API Key"

    let keychain: KeychainAccessing

    init(keychain: KeychainAccessing = SecurityKeychainAccessor()) {
        self.keychain = keychain
    }

    func loadKey() -> String? {
        guard let value = try? keychain.readGenericPasswordForCurrentUser(
            service: Self.service
        ) else {
            return nil
        }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    var hasKey: Bool { loadKey() != nil }

    func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderFailure(
                .authentication,
                "Enter a DeepSeek API key."
            )
        }
        try keychain.writeGenericPasswordForCurrentUser(
            service: Self.service,
            value: trimmed
        )
    }

    func removeKey() throws {
        try keychain.deleteGenericPasswordForCurrentUser(service: Self.service)
    }
}
