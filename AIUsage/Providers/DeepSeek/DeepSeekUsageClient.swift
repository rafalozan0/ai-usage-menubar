import Foundation

struct DeepSeekUsageClient: Sendable {
    static let balanceURL = URL(
        string: "https://api.deepseek.com/user/balance"
    )!

    let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func fetchBalance(apiKey: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: .get,
            url: Self.balanceURL,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json",
                "User-Agent": "AIUsage/0.1"
            ]
        ))
    }
}
