import Foundation

enum DeepSeekUsageMapper {
    struct Balance: Equatable, Sendable {
        let amount: Double
        let currencyCode: String
    }

    static func balance(from response: HTTPResponse) throws -> Balance {
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderFailure(
                response.statusCode >= 500 ? .transient : .invalidResponse,
                "DeepSeek balance request failed (\(response.statusCode))."
            )
        }
        let body = try ProviderParsing.object(from: response.body)
        let balances = ProviderParsing.array(body["balance_infos"])
        // Prefer the USD wallet, otherwise show whatever currency the account
        // is funded in.
        let selected = balances.first {
            ProviderParsing.string($0["currency"])?.uppercased() == "USD"
        } ?? balances.first
        guard let selected,
              let currency = ProviderParsing.string(selected["currency"]),
              let total = ProviderParsing.double(selected["total_balance"]) else {
            throw ProviderFailure(
                .invalidResponse,
                "DeepSeek balance response changed."
            )
        }
        return Balance(
            amount: max(total, 0),
            currencyCode: currency.uppercased()
        )
    }

    /// The bar runs from the starting balance down to zero.
    static func snapshot(
        balance: Balance,
        startingBalance: Double,
        now: Date
    ) -> ProviderSnapshot {
        let start = max(startingBalance, balance.amount)
        let usedPercent = start > 0
            ? min(max((start - balance.amount) / start * 100, 0), 100)
            : 100

        return ProviderSnapshot(
            provider: .deepseek,
            planName: "API",
            windows: [
                QuotaWindow(
                    kind: .credits,
                    usedPercent: usedPercent,
                    resetsAt: nil
                )
            ],
            billingUsage: .balance(
                amount: balance.amount,
                currencyCode: balance.currencyCode
            ),
            fetchedAt: now
        )
    }
}
