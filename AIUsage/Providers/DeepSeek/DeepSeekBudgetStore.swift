import Foundation

/// Remembers the balance the bar is measured against.
///
/// DeepSeek only reports what is left, so the starting balance is captured on
/// the first read, raised when the account is topped up, and can be edited in
/// Settings. It is a single number, not a usage history.
struct DeepSeekBudgetStore: @unchecked Sendable {
    private enum Key {
        static let amount = "deepSeekStartingBalance"
        static let currency = "deepSeekStartingBalanceCurrency"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func startingBalance(currencyCode: String) -> Double? {
        guard defaults.string(forKey: Key.currency) == currencyCode,
              defaults.object(forKey: Key.amount) != nil else {
            return nil
        }
        let amount = defaults.double(forKey: Key.amount)
        return amount > 0 ? amount : nil
    }

    func setStartingBalance(_ amount: Double, currencyCode: String) {
        defaults.set(amount, forKey: Key.amount)
        defaults.set(currencyCode, forKey: Key.currency)
    }

    /// Returns the starting balance to measure against, capturing or raising
    /// it when the current balance is higher than what was stored.
    func resolveStartingBalance(
        current: Double,
        currencyCode: String
    ) -> Double {
        if let stored = startingBalance(currencyCode: currencyCode),
           stored >= current {
            return stored
        }
        setStartingBalance(current, currencyCode: currencyCode)
        return current
    }

    func clear() {
        defaults.removeObject(forKey: Key.amount)
        defaults.removeObject(forKey: Key.currency)
    }
}
