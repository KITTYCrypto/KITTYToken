import SwiftUI
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedTab: MobileTab = .command
    @Published var backendURL: String = UserDefaults.standard.string(forKey: "chainscope_backend_url") ?? "https://api.socacrypto.com"
    @Published var apiKey: String = KeychainStore.read(KeychainStore.apiKey)
    @Published var directorLabel: String = UserDefaults.standard.string(forKey: "chainscope_director_label") ?? ""
    @Published var accessCode: String = ""
    @Published var walletChain: String = UserDefaults.standard.string(forKey: "chainscope_wallet_chain") ?? "solana"
    @Published var walletAddress: String = ""
    @Published var coinbaseKeyName: String = ""
    @Published var coinbasePrivateKey: String = ""
    @Published var coinbasePortfolioID: String = ""
    @Published var coinbaseQuoteCurrency: String = UserDefaults.standard.string(forKey: "chainscope_coinbase_quote") ?? "USD"
    @Published var solanaPublicAddress: String = ""
    @Published var solanaPrivateKey: String = ""
    @Published var dashboard: JSONObject = [:]
    @Published var live: JSONObject = [:]
    @Published var statusText: String = "Ready"
    @Published var isLoading = false
    @Published var showSettings = false
    @Published var apnsToken: String = ""

    private var api = ChainScopeAPI(baseURL: "https://api.socacrypto.com")
    private var bootstrapped = false

    var hasPrivateAccess: Bool {
        !apiKey.trimmed.isEmpty
    }

    var hasDirectorSession: Bool {
        !KeychainStore.read(KeychainStore.directorToken).isEmpty
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        NotificationCenter.default.addObserver(forName: .apnsTokenDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self, let token = note.object as? String else { return }
            Task { @MainActor in
                self.apnsToken = token
                if !token.isEmpty {
                    await self.registerPushTokenIfPossible()
                }
            }
        }
        await reload()
    }

    func saveSettings() async {
        UserDefaults.standard.set(backendURL.trimmed, forKey: "chainscope_backend_url")
        UserDefaults.standard.set(directorLabel.trimmed, forKey: "chainscope_director_label")
        UserDefaults.standard.set(walletChain.trimmed, forKey: "chainscope_wallet_chain")
        UserDefaults.standard.set(coinbaseQuoteCurrency.trimmed.uppercased(), forKey: "chainscope_coinbase_quote")
        if apiKey.trimmed.isEmpty {
            KeychainStore.delete(KeychainStore.apiKey)
        } else {
            KeychainStore.save(apiKey.trimmed, account: KeychainStore.apiKey)
        }
        await configureAPI()
        await registerPushTokenIfPossible()
        await reload()
    }

    func reload() async {
        isLoading = true
        statusText = "Refreshing ChainScope..."
        await configureAPI()
        do {
            async let dashboardPayload = api.dashboard()
            let loadedDashboard = try await dashboardPayload
            dashboard = loadedDashboard
            if hasPrivateAccess || hasDirectorSession {
                do {
                    live = try await api.liveConnections()
                } catch {
                    live = loadedDashboard.object("live_trading")
                }
            } else {
                live = loadedDashboard.object("live_trading")
            }
            statusText = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
        } catch {
            statusText = "Refresh failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func startDirectorSession() async {
        guard !directorLabel.trimmed.isEmpty, !accessCode.trimmed.isEmpty else {
            statusText = "Director name and access code are required."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Starting Director Portal session..."
        do {
            let payload = try await api.startDirectorSession(directorLabel: directorLabel, accessCode: accessCode)
            let token = payload.string("director_token", payload.object("data").string("director_token"))
            if !token.isEmpty {
                KeychainStore.save(token, account: KeychainStore.directorToken)
            }
            accessCode = ""
            statusText = "Director session active."
            await reload()
        } catch {
            statusText = "Director session failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func endDirectorSession() async {
        KeychainStore.delete(KeychainStore.directorToken)
        statusText = "Director session cleared on this phone."
        await reload()
    }

    func registerPublicWallet() async {
        guard !walletAddress.trimmed.isEmpty else {
            statusText = "Paste a public wallet address first."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Registering public wallet..."
        do {
            live = try await api.registerPublicWallet(directorLabel: directorLabel, chain: walletChain, walletAddress: walletAddress)
            walletAddress = ""
            statusText = "Wallet connection registered."
            await reload()
        } catch {
            statusText = "Wallet registration failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func registerCoinbaseKey() async {
        guard !coinbaseKeyName.trimmed.isEmpty, !coinbasePrivateKey.trimmed.isEmpty else {
            statusText = "Paste the Coinbase key name and private key first."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Validating Coinbase Secret API Key..."
        do {
            let nickname = directorLabel.trimmed.isEmpty ? "Coinbase Secret API Key" : "\(directorLabel.trimmed) Coinbase"
            live = try await api.registerCoinbaseAPIKey(
                keyName: coinbaseKeyName,
                privateKey: coinbasePrivateKey,
                portfolioID: coinbasePortfolioID,
                quoteCurrency: coinbaseQuoteCurrency,
                nickname: nickname
            )
            coinbasePrivateKey = ""
            statusText = "Coinbase Secret API Key registered and encrypted."
            await reload()
        } catch {
            statusText = "Coinbase key failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func registerSolanaHotWallet() async {
        guard solanaPrivateKey.trimmed.count >= 32 else {
            statusText = "Paste a Solana keypair JSON, base58 secret, or base64 secret key."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Validating Solana executor wallet..."
        do {
            let nickname = directorLabel.trimmed.isEmpty ? "Solana Executor Wallet" : "\(directorLabel.trimmed) Solana Executor"
            live = try await api.registerSolanaHotWallet(publicAddress: solanaPublicAddress, privateKey: solanaPrivateKey, nickname: nickname)
            solanaPrivateKey = ""
            statusText = "Solana executor wallet registered and encrypted."
            await reload()
        } catch {
            statusText = "Solana executor wallet failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func disconnect(_ connection: JSONObject) async {
        let id = connection.int("id")
        guard id > 0 else {
            statusText = "Connection ID missing."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Disconnecting connection..."
        do {
            live = try await api.disconnect(connectionID: id)
            statusText = "Connection disconnected."
            await reload()
        } catch {
            statusText = "Disconnect failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func openWalletSigner(_ approval: JSONObject, preferredWallet: String) async {
        let approvalID = approval.int("approval_id", approval.int("id"))
        guard approvalID > 0 else {
            statusText = "Approval ID missing."
            return
        }
        await configureAPI()
        isLoading = true
        statusText = "Preparing mobile wallet signer..."
        do {
            let payload = try await api.mobileWalletLink(approvalID: approvalID, preferredWallet: preferredWallet)
            let chain = approval.string("chain").lowercased()
            var link = ""
            if preferredWallet == "phantom" || (preferredWallet == "auto" && chain.contains("sol")) {
                link = payload.string("phantom_url")
            } else if preferredWallet == "metamask" || preferredWallet == "auto" {
                link = payload.string("metamask_url")
            }
            if link.isEmpty {
                link = payload.string("sign_url")
            }
            guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) || url.scheme?.hasPrefix("http") == true else {
                statusText = "ChainScope did not return an installed wallet link."
                isLoading = false
                return
            }
            UIApplication.shared.open(url)
            statusText = "Wallet signer opened."
        } catch {
            statusText = "Wallet signer failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func handleDeepLink(_ url: URL) {
        statusText = "Returned from wallet: \(url.host ?? "chainscope")"
        Task {
            await reload()
        }
    }

    private func configureAPI() async {
        await api.update(baseURL: backendURL, apiKey: apiKey, directorToken: KeychainStore.read(KeychainStore.directorToken))
    }

    private func registerPushTokenIfPossible() async {
        guard !apnsToken.isEmpty, hasPrivateAccess else { return }
        await configureAPI()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.chainscope.mobile.ios"
        do {
            _ = try await api.registerPushToken(token: apnsToken, appVersion: version, bundleID: bundleID)
            statusText = "iOS push device registered."
        } catch {
            statusText = "Push registration failed: \(error.localizedDescription)"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x06111A), Color(hex: 0x0B1724)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    Picker("Section", selection: $model.selectedTab) {
                        ForEach(MobileTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    ScrollView {
                        VStack(spacing: 14) {
                            switch model.selectedTab {
                            case .command:
                                CommandView()
                            case .board:
                                BoardView()
                            case .signals:
                                SignalsView()
                            case .ops:
                                OpsView()
                            case .live:
                                LiveTradeView()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                    statusBar
                }
            }
            .sheet(isPresented: $model.showSettings) {
                SettingsView()
                    .environmentObject(model)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: 0x02E7C9), Color(hex: 0x156BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "link")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("ChainScope AI")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.hasPrivateAccess ? "Private dashboard" : "Public dashboard")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x9DB5C9))
            }

            Spacer()

            Button {
                Task { await model.reload() }
            } label: {
                Image(systemName: model.isLoading ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.statusText.lowercased().contains("failed") ? Color(hex: 0xFF5876) : Color(hex: 0x20F0C3))
                .frame(width: 8, height: 8)
            Text(model.statusText)
                .lineLimit(2)
                .font(.caption)
                .foregroundStyle(Color(hex: 0xBBD1E5))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x071019))
    }
}

struct CommandView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        let summary = model.dashboard.object("summary")
        let scan = model.dashboard.object("scan_health")
        VStack(spacing: 12) {
            MetricGrid(metrics: [
                ("API", model.dashboard.bool("ok") ? "OK" : "Check", model.backendURL.shortID(prefix: 18, suffix: 0)),
                ("Scanner", scan.string("status", "unknown").capitalized, "age \(String(format: "%.1f", scan.double("age_minutes")))m"),
                ("Signals", "\(summary.int("signals_count", model.dashboard.int("signals_count")))", "current board"),
                ("Alerts", "\(summary.int("alerts_fired", model.dashboard.int("alerts_fired")))", "last scan")
            ])
            Panel(title: "Command Center", eyebrow: "HEALTH") {
                KeyValueRow("Dashboard", value: model.dashboard.bool("ok") ? "healthy" : "loaded")
                KeyValueRow("Private access", value: model.hasPrivateAccess ? "configured" : "public")
                KeyValueRow("Director session", value: model.hasDirectorSession ? "active" : "not active")
                KeyValueRow("Push token", value: model.apnsToken.isEmpty ? "waiting for APNs" : "device token ready")
            }
            let explanation = model.dashboard.object("no_trade_explainability")
            if !explanation.isEmpty {
                Panel(title: "No-Trade Read", eyebrow: "MARKET") {
                    Text(explanation.string("headline", "No-trade details loaded."))
                        .bodyText()
                    ForEach(explanation.array("reasons").prefix(4).indices, id: \.self) { index in
                        let reason = explanation.array("reasons")[index]
                        KeyValueRow(reason.string("label", "Reason"), value: reason.string("detail", "waiting"))
                    }
                }
            }
        }
    }
}

struct BoardView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        let board = model.dashboard.array("board")
        let candidates = board.isEmpty ? model.dashboard.array("buy_cards") : board
        VStack(spacing: 12) {
            if candidates.isEmpty {
                EmptyPanel(title: "Board", text: "No current board cards were returned by the API.")
            } else {
                ForEach(Array(candidates.prefix(20).enumerated()), id: \.offset) { _, item in
                    Panel(title: item.string("symbol", item.string("token", "Token")), eyebrow: item.string("chain", "BOARD").uppercased()) {
                        KeyValueRow("Score", value: item.string("score", String(format: "%.2f", item.double("score"))))
                        KeyValueRow("Liquidity", value: item.string("liquidity_usd", "$\(String(format: "%.0f", item.double("liquidity_usd")))"))
                        Text(item.string("reason", item.string("status", "No detail supplied.")))
                            .bodyText()
                    }
                }
            }
        }
    }
}

struct SignalsView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        let signals = model.dashboard.array("signals")
        let recent = signals.isEmpty ? model.dashboard.array("recent_signals") : signals
        VStack(spacing: 12) {
            if recent.isEmpty {
                EmptyPanel(title: "Signals", text: "No signal rows were returned by the API.")
            } else {
                ForEach(Array(recent.prefix(20).enumerated()), id: \.offset) { _, signal in
                    Panel(title: signal.string("symbol", signal.string("token", "Signal")), eyebrow: signal.string("side", "SIGNAL").uppercased()) {
                        KeyValueRow("Confidence", value: signal.string("confidence", String(format: "%.2f", signal.double("confidence"))))
                        KeyValueRow("Status", value: signal.string("status", "observed"))
                        Text(signal.string("reason", signal.string("note", "No reason supplied.")))
                            .bodyText()
                    }
                }
            }
        }
    }
}

struct OpsView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        let valuation = model.dashboard.object("self_custody_valuation")
        let premium = model.dashboard.object("premium_intelligence")
        let replay = model.dashboard.object("replay_lab")
        VStack(spacing: 12) {
            Panel(title: "Route-Verified Wallet Value", eyebrow: "VALUATION") {
                KeyValueRow("Status", value: valuation.string("status", "not loaded"))
                KeyValueRow("Counted", value: "\(valuation.int("counted_tokens"))")
                KeyValueRow("Excluded", value: "\(valuation.int("excluded_tokens"))")
                KeyValueRow("Value", value: "$\(String(format: "%.2f", valuation.double("total_route_verified_usd")))")
            }
            Panel(title: "Premium Intelligence", eyebrow: "EDGE") {
                KeyValueRow("Status", value: premium.string("status", "not loaded"))
                KeyValueRow("Smart wallet", value: premium.string("smart_wallet_edge", premium.string("smart_wallet_status", "unknown")))
                KeyValueRow("Rollups", value: "\(premium.int("rollups_count"))")
            }
            Panel(title: "Replay Lab", eyebrow: "EXIT DATA") {
                KeyValueRow("Status", value: replay.string("status", "not loaded"))
                KeyValueRow("Samples", value: "\(replay.int("samples", replay.int("replay_count")))")
            }
        }
    }
}

struct LiveTradeView: View {
    @EnvironmentObject private var model: DashboardViewModel

    var liveData: JSONObject {
        let data = model.live.object("data")
        return data.isEmpty ? model.live : data
    }

    var connections: [JSONObject] {
        let primary = liveData.array("connections")
        if !primary.isEmpty { return primary }
        return model.dashboard.object("live_trading").array("connections")
    }

    var approvals: [JSONObject] {
        let primary = liveData.array("wallet_approvals")
        if !primary.isEmpty { return primary }
        return model.dashboard.object("live_trading").array("wallet_approvals")
    }

    var body: some View {
        VStack(spacing: 12) {
            Panel(title: "Director Portal", eyebrow: model.hasDirectorSession ? "SESSION ACTIVE" : "DIRECTOR SIGN-IN") {
                TextField("Director name", text: $model.directorLabel)
                    .textInput()
                SecureField("Director access code", text: $model.accessCode)
                    .textInput()
                HStack {
                    Button("Start Session") {
                        Task { await model.startDirectorSession() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Clear") {
                        Task { await model.endDirectorSession() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            Panel(title: "Public Self-Custody Wallet", eyebrow: "TRACKING") {
                Text("Register public wallet addresses for director routing. Do not paste seed phrases here.")
                    .bodyText()
                Picker("Chain", selection: $model.walletChain) {
                    Text("Solana").tag("solana")
                    Text("ETH / EVM").tag("eth")
                }
                .pickerStyle(.segmented)
                TextField("Public wallet address", text: $model.walletAddress)
                    .textInput()
                Button("Register Wallet") {
                    Task { await model.registerPublicWallet() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Panel(title: "Coinbase Secret API Key", eyebrow: "EXCHANGE") {
                Text("Use an ECDSA/ES256 Coinbase Secret API Key. The private key is sent to ChainScope for encrypted server storage and then cleared from this screen.")
                    .bodyText()
                TextField("Key name", text: $model.coinbaseKeyName)
                    .textInput()
                    .textInputAutocapitalization(.never)
                SecureField("ECDSA private key PEM", text: $model.coinbasePrivateKey)
                    .textInput()
                TextField("Optional portfolio ID", text: $model.coinbasePortfolioID)
                    .textInput()
                    .textInputAutocapitalization(.never)
                Picker("Quote", selection: $model.coinbaseQuoteCurrency) {
                    Text("USD").tag("USD")
                    Text("USDC").tag("USDC")
                }
                .pickerStyle(.segmented)
                Button("Register Coinbase Key") {
                    Task { await model.registerCoinbaseKey() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Panel(title: "Solana Executor Wallet", eyebrow: "HOT WALLET") {
                Text("Use a separate capped trading wallet only. Seed phrases are rejected; paste a Solana keypair JSON, base58 secret, or base64 secret key.")
                    .bodyText()
                TextField("Optional public address check", text: $model.solanaPublicAddress)
                    .textInput()
                    .textInputAutocapitalization(.never)
                SecureField("Solana private key material", text: $model.solanaPrivateKey)
                    .textInput()
                Button("Register Solana Executor Wallet") {
                    Task { await model.registerSolanaHotWallet() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if !approvals.isEmpty {
                Panel(title: "Pending Wallet Approvals", eyebrow: "NATIVE SIGNING") {
                    ForEach(Array(approvals.prefix(12).enumerated()), id: \.offset) { _, approval in
                        if approval.string("status", "PENDING").uppercased() == "PENDING" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(approval.string("action", "Approval")) #\(approval.int("approval_id", approval.int("id")))")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(approval.string("message", "Open your wallet to sign this ChainScope approval."))
                                    .bodyText()
                                HStack {
                                    Button("Open Phantom") {
                                        Task { await model.openWalletSigner(approval, preferredWallet: "phantom") }
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    Button("Signer Link") {
                                        Task { await model.openWalletSigner(approval, preferredWallet: "auto") }
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }

            Panel(title: "Registered Connections", eyebrow: "\(connections.count) ACTIVE/RECENT") {
                if connections.isEmpty {
                    Text("No director exchange accounts or wallets registered yet.")
                        .bodyText()
                } else {
                    ForEach(Array(connections.prefix(18).enumerated()), id: \.offset) { _, connection in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.string("director_label", "Director"))
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text("\(connection.string("provider").replacingOccurrences(of: "_", with: " ")) | \(connection.string("chain", connection.string("connection_type")).uppercased())")
                                        .font(.caption)
                                        .foregroundStyle(Color(hex: 0x9DB5C9))
                                }
                                Spacer()
                                Text(connection.string("status", "ACTIVE").uppercased())
                                    .pill(color: connection.string("status").lowercased().contains("disconnect") ? Color(hex: 0xFF5876) : Color(hex: 0x20F0C3))
                            }
                            Text(connection.string("wallet_address", connection.string("external_account_ref", "account pending")).shortID())
                                .bodyText()
                            Button("Disconnect") {
                                Task { await model.disconnect(connection) }
                            }
                            .buttonStyle(DangerButtonStyle())
                        }
                        .padding(.vertical, 8)
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: DashboardViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("ChainScope Backend") {
                    TextField("Backend URL", text: $model.backendURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Dashboard API key", text: $model.apiKey)
                    Text("Leave the API key blank for the public dashboard. Private live-trade features require a key or Director Portal session.")
                        .font(.caption)
                }
                Section("Device") {
                    Text("APNs token: \(model.apnsToken.isEmpty ? "waiting" : "ready")")
                    Text("Bundle: \(Bundle.main.bundleIdentifier ?? "ai.chainscope.mobile.ios")")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.saveSettings()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct MetricGrid: View {
    let metrics: [(String, String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 7) {
                    Text(metric.0.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x20F0C3))
                    Text(metric.1)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(metric.2)
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x9DB5C9))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(panelBackground)
            }
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x20F0C3))
                    Text(title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(panelBackground)
    }
}

struct EmptyPanel: View {
    let title: String
    let text: String

    var body: some View {
        Panel(title: title, eyebrow: "EMPTY") {
            Text(text).bodyText()
        }
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: 0x9DB5C9))
            Spacer()
            Text(value.isEmpty ? "n/a" : value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private var panelBackground: some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(Color(hex: 0x101B26).opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(hex: 0x031016))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: configuration.isPressed ? 0x11BFA5 : 0x20F0C3)))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10)))
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x532032).opacity(configuration.isPressed ? 1 : 0.9)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xFF5876).opacity(0.55), lineWidth: 1))
    }
}

extension Text {
    func bodyText() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(Color(hex: 0xBBD1E5))
            .fixedSize(horizontal: false, vertical: true)
    }

    func pill(color: Color) -> some View {
        self
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
    }
}

extension View {
    func textInput() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x071019)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
