import XCTest
@testable import AIUsage

final class DeepSeekTests: XCTestCase {
    private let balanceJSON = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "50.00",
          "granted_balance": "0.00",
          "topped_up_balance": "50.00"
        },
        {
          "currency": "USD",
          "total_balance": "12.34",
          "granted_balance": "2.34",
          "topped_up_balance": "10.00"
        }
      ]
    }
    """

    func testMapperPrefersUSDBalance() throws {
        let snapshot = try DeepSeekUsageMapper.map(
            response: httpResponse(json: balanceJSON),
            now: Date()
        )

        XCTAssertEqual(snapshot.provider, .deepseek)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(
            snapshot.billingUsage,
            .balance(amount: 12.34, currencyCode: "USD")
        )
    }

    func testMapperFallsBackToFirstCurrency() throws {
        let snapshot = try DeepSeekUsageMapper.map(
            response: httpResponse(json: """
            {"balance_infos":[{"currency":"CNY","total_balance":"7.5"}]}
            """),
            now: Date()
        )

        XCTAssertEqual(
            snapshot.billingUsage,
            .balance(amount: 7.5, currencyCode: "CNY")
        )
    }

    func testMapperRejectsUnexpectedShape() {
        XCTAssertThrowsError(try DeepSeekUsageMapper.map(
            response: httpResponse(json: #"{"balance_infos":[]}"#),
            now: Date()
        ))
    }

    func testProviderSendsBearerKeyFromKeychain() async throws {
        let keychain = MemoryKeychain(currentUser: [
            DeepSeekKeyStore.service: "sk-test"
        ])
        let http = MockHTTPClient([httpResponse(json: balanceJSON)])
        let provider = DeepSeekProvider(
            keyStore: DeepSeekKeyStore(keychain: keychain),
            client: DeepSeekUsageClient(http: http)
        )

        _ = try await provider.fetch()

        let requests = await http.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, DeepSeekUsageClient.balanceURL)
        XCTAssertEqual(
            requests.first?.headers["Authorization"],
            "Bearer sk-test"
        )
    }

    func testProviderRequiresStoredKey() async {
        let provider = DeepSeekProvider(
            keyStore: DeepSeekKeyStore(keychain: MemoryKeychain()),
            client: DeepSeekUsageClient(http: MockHTTPClient([]))
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected an authentication failure")
        } catch let failure as ProviderFailure {
            XCTAssertEqual(failure.kind, .authentication)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testProviderReportsRejectedKey() async {
        let provider = DeepSeekProvider(
            keyStore: DeepSeekKeyStore(keychain: MemoryKeychain(currentUser: [
                DeepSeekKeyStore.service: "sk-bad"
            ])),
            client: DeepSeekUsageClient(
                http: MockHTTPClient([httpResponse(401)])
            )
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected an authentication failure")
        } catch let failure as ProviderFailure {
            XCTAssertEqual(failure.kind, .authentication)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testKeyStoreSavesAndRemovesKey() throws {
        let keychain = MemoryKeychain()
        let store = DeepSeekKeyStore(keychain: keychain)
        XCTAssertFalse(store.hasKey)

        try store.save("  sk-test \n")
        XCTAssertEqual(store.loadKey(), "sk-test")

        try store.removeKey()
        XCTAssertFalse(store.hasKey)
        XCTAssertThrowsError(try store.save("   "))
    }

    func testBalancePresentationAndMenuBarValue() {
        let usage = BillingUsage.balance(amount: 12.34, currencyCode: "USD")
        let presentation = BillingUsagePresentation(
            usage: usage,
            displayMode: .remaining,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(presentation.title, "Balance")
        XCTAssertEqual(presentation.valueText, "$12.34 left")
        XCTAssertEqual(
            usage.menuBarValue(displayMode: .used),
            .money(amount: 12.34, currencyCode: "USD")
        )
    }
}
