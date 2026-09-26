import Foundation

enum DeepSeekUsageMapper {
    static func map(
        response: HTTPResponse,
        now: Date
    ) throws -> ProviderSnapshot {
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

        return ProviderSnapshot(
            provider: .deepseek,
            planName: "API",
            windows: [],
            billingUsage: .balance(
                amount: max(total, 0),
                currencyCode: currency.uppercased()
            ),
            fetchedAt: now
        )
    }
}
