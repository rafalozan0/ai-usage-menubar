import Foundation

actor DeepSeekProvider: UsageProvider {
    nonisolated let id = ProviderID.deepseek

    private let keyStore: DeepSeekKeyStore
    private let client: DeepSeekUsageClient
    private let dateProvider: DateProviding

    init(
        keyStore: DeepSeekKeyStore = DeepSeekKeyStore(),
        client: DeepSeekUsageClient = DeepSeekUsageClient(),
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.keyStore = keyStore
        self.client = client
        self.dateProvider = dateProvider
    }

    func fetch() async throws -> ProviderSnapshot {
        guard let apiKey = keyStore.loadKey() else {
            throw ProviderFailure(
                .authentication,
                "Add your DeepSeek API key in Settings."
            )
        }

        let response: HTTPResponse
        do {
            response = try await client.fetchBalance(apiKey: apiKey)
        } catch {
            throw ProviderFailure(
                .transient,
                "DeepSeek could not be reached."
            )
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ProviderFailure(
                .authentication,
                "DeepSeek rejected the API key. Update it in Settings."
            )
        }
        return try DeepSeekUsageMapper.map(
            response: response,
            now: dateProvider.now()
        )
    }
}
