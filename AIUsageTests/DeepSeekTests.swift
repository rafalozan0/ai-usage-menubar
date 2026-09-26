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

    private func makeBudget() -> DeepSeekBudgetStore {
        let defaults = UserDefaults(
            suiteName: "DeepSeekTests.\(UUID().uuidString)"
        )!
        return DeepSeekBudgetStore(defaults: defaults)
    }

    func testMapperPrefersUSDBalance() throws {
        let balance = try DeepSeekUsageMapper.balance(
            from: httpResponse(json: balanceJSON)
        )

        XCTAssertEqual(
            balance,
            DeepSeekUsageMapper.Balance(amount: 12.34, currencyCode: "USD")
        )
    }

    func testMapperFallsBackToFirstCurrency() throws {
        let balance = try DeepSeekUsageMapper.balance(
            from: httpResponse(json: """
            {"balance_infos":[{"currency":"CNY","total_balance":"7.5"}]}
            """)
        )

        XCTAssertEqual(
            balance,
            DeepSeekUsageMapper.Balance(amount: 7.5, currencyCode: "CNY")
        )
    }

    func testMapperRejectsUnexpectedShape() {
        XCTAssertThrowsError(try DeepSeekUsageMapper.balance(
            from: httpResponse(json: #"{"balance_infos":[]}"#)
        ))
    }

    func testBarRunsFromStartingBalanceToZero() {
        let balance = DeepSeekUsageMapper.Balance(
            amount: 6.95,
            currencyCode: "USD"
        )
        let snapshot = DeepSeekUsageMapper.snapshot(
            balance: balance,
            startingBalance: 9.27,
            now: Date()
        )

        XCTAssertEqual(snapshot.provider, .deepseek)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.credits])
        XCTAssertEqual(
            snapshot.windows[0].usedPercent,
            25,
            accuracy: 0.1
        )
        XCTAssertEqual(
            snapshot.billingUsage,
            .balance(amount: 6.95, currencyCode: "USD")
        )
    }

    func testBarIsEmptyAtZeroBalance() {
        let snapshot = DeepSeekUsageMapper.snapshot(
            balance: .init(amount: 0, currencyCode: "USD"),
            startingBalance: 9.27,
            now: Date()
        )

        XCTAssertEqual(snapshot.windows[0].usedPercent, 100)
    }

    func testBudgetCapturesFirstBalanceAndRaisesOnTopUp() {
        let budget = makeBudget()

        XCTAssertEqual(
            budget.resolveStartingBalance(current: 9.27, currencyCode: "USD"),
            9.27
        )
        XCTAssertEqual(
            budget.resolveStartingBalance(current: 5, currencyCode: "USD"),
            9.27
        )
        XCTAssertEqual(
            budget.resolveStartingBalance(current: 20, currencyCode: "USD"),
            20
        )
        XCTAssertNil(budget.startingBalance(currencyCode: "CNY"))
    }

    func testProviderSendsBearerKeyFromKeychain() async throws {
        let keychain = MemoryKeychain(currentUser: [
            DeepSeekKeyStore.service: "sk-test"
        ])
        let http = MockHTTPClient([httpResponse(json: balanceJSON)])
        let provider = DeepSeekProvider(
            keyStore: DeepSeekKeyStore(keychain: keychain),
            client: DeepSeekUsageClient(http: http),
            budget: makeBudget()
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.windows[0].usedPercent, 0)

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
