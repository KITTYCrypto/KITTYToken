import Foundation

actor ChainScopeAPI {
    private var baseURL: URL
    private var apiKey: String
    private var directorToken: String

    init(baseURL: String, apiKey: String = "", directorToken: String = "") {
        self.baseURL = URL(string: baseURL) ?? URL(string: "https://api.socacrypto.com")!
        self.apiKey = apiKey
        self.directorToken = directorToken
    }

    func update(baseURL: String, apiKey: String, directorToken: String) {
        self.baseURL = URL(string: baseURL.trimmed) ?? URL(string: "https://api.socacrypto.com")!
        self.apiKey = apiKey.trimmed
        self.directorToken = directorToken.trimmed
    }

    func dashboard() async throws -> JSONObject {
        try await request(apiKey.isEmpty ? "/api/public/dashboard" : "/api/dashboard", method: "GET", body: nil, publicRead: apiKey.isEmpty)
    }

    func liveConnections() async throws -> JSONObject {
        try await request("/api/live-trading/connections")
    }

    func liveStatus() async throws -> JSONObject {
        try await request("/api/live-trading/status")
    }

    func startDirectorSession(directorLabel: String, accessCode: String) async throws -> JSONObject {
        try await request("/api/director-portal/session", method: "POST", body: [
            "director_label": directorLabel.trimmed,
            "access_code": accessCode.trimmed
        ])
    }

    func registerCoinbaseAPIKey(keyName: String, privateKey: String, portfolioID: String, quoteCurrency: String, nickname: String) async throws -> JSONObject {
        try await request("/api/live-trading/connect/coinbase/api-key", method: "POST", body: [
            "key_name": keyName.trimmed,
            "private_key": privateKey.trimmed,
            "portfolio_id": portfolioID.trimmed,
            "quote_currency": quoteCurrency.trimmed.uppercased() == "USDC" ? "USDC" : "USD",
            "nickname": nickname.trimmed
        ])
    }

    func registerSolanaHotWallet(publicAddress: String, privateKey: String, nickname: String) async throws -> JSONObject {
        try await request("/api/live-trading/connect/solana-hot-wallet", method: "POST", body: [
            "wallet_address": publicAddress.trimmed,
            "private_key": privateKey.trimmed,
            "nickname": nickname.trimmed
        ])
    }

    func registerPublicWallet(directorLabel: String, chain: String, walletAddress: String) async throws -> JSONObject {
        try await request("/api/live-trading/connections", method: "POST", body: [
            "provider": "self_custody_wallet",
            "connection_type": "wallet",
            "director_label": directorLabel.trimmed,
            "chain": normalizedChain(chain),
            "wallet_address": walletAddress.trimmed,
            "wallet_client": "ios_manual"
        ])
    }

    func disconnect(connectionID: Int) async throws -> JSONObject {
        try await request("/api/live-trading/connections/\(connectionID)/disconnect", method: "POST", body: [
            "reason": "ios_disconnect"
        ])
    }

    func mobileWalletLink(approvalID: Int, preferredWallet: String) async throws -> JSONObject {
        try await request("/api/live-trading/wallet-approvals/mobile-link", method: "POST", body: [
            "approval_id": approvalID,
            "preferred_wallet": preferredWallet
        ])
    }

    func registerPushToken(token: String, appVersion: String, bundleID: String) async throws -> JSONObject {
        try await request("/api/mobile/push-token", method: "POST", body: [
            "token": token.trimmed,
            "platform": "ios",
            "app_version": appVersion,
            "package_name": bundleID
        ])
    }

    private func normalizedChain(_ value: String) -> String {
        let chain = value.trimmed.lowercased()
        if chain == "sol" { return "solana" }
        if chain == "ethereum" || chain == "evm" { return "eth" }
        return chain == "solana" ? "solana" : "eth"
    }

    private func request(_ path: String, method: String = "GET", body: JSONObject? = nil, publicRead: Bool = false) async throws -> JSONObject {
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/\(cleanPath)") else {
            throw ChainScopeError(message: "Invalid ChainScope URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ChainScopeAI-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        if !publicRead && !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-ChainScope-Key")
        }
        if !directorToken.isEmpty {
            request.setValue(directorToken, forHTTPHeaderField: "X-ChainScope-Director-Token")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let preview = String(data: Data(data.prefix(220)), encoding: .utf8) ?? ""
            throw ChainScopeError(message: "HTTP \(code): \(preview)")
        }
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        if let object = parsed as? JSONObject {
            return object
        }
        return ["ok": true]
    }
}
