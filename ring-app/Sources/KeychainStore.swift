import Foundation
import Security

// MARK: - ProviderStatus

struct ProviderStatus: Identifiable {
    let provider: Provider
    var configured: Bool    // has client_id or api_key?
    var connected: Bool     // has a valid access_token?
    var entry: TokenEntry?
    var needsRefresh: Bool

    var id: String { provider.id }

    var statusColor: StatusColor {
        if !configured { return .grey }
        if !connected  { return .grey }
        if needsRefresh { return .yellow }
        return .green
    }

    enum StatusColor { case green, yellow, grey }
}

// MARK: - KeychainStore

/// Reads and writes the macOS Keychain using the exact same service name and key
/// convention as the Go CLI, so both components share a single source of truth.
@MainActor
final class KeychainStore: ObservableObject {

    // MUST match `const Service = "com.ring.tokenstore"` in the Go CLI
    static let service = "com.ring.tokenstore"

    @Published var providers: [ProviderStatus] = []

    init() {
        refresh()
    }

    // MARK: - Low-level primitives

    func getString(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      Self.service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    func setString(_ account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func delete(_ account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func exists(_ account: String) -> Bool {
        getString(account) != nil
    }

    // MARK: - Token entry (OAuth2)

    func getEntry(_ providerID: String) -> TokenEntry? {
        guard let at = getString("\(providerID).access_token") else { return nil }
        let rt = getString("\(providerID).refresh_token") ?? ""
        let scopes = getString("\(providerID).scopes").map { $0.split(separator: ",").map(String.init) } ?? []

        var expiresAt: Date?
        if let expiresStr = getString("\(providerID).expires_at") {
            expiresAt = ISO8601DateFormatter().date(from: expiresStr)
        }

        return TokenEntry(accessToken: at, refreshToken: rt, expiresAt: expiresAt, scopes: scopes)
    }

    func setEntry(_ providerID: String, entry: TokenEntry) {
        setString("\(providerID).access_token", value: entry.accessToken)
        if !entry.refreshToken.isEmpty {
            setString("\(providerID).refresh_token", value: entry.refreshToken)
        }
        if let expiresAt = entry.expiresAt {
            setString("\(providerID).expires_at", value: ISO8601DateFormatter().string(from: expiresAt))
        }
        if !entry.scopes.isEmpty {
            setString("\(providerID).scopes", value: entry.scopes.joined(separator: ","))
        }
    }

    func clearTokens(_ providerID: String) {
        delete("\(providerID).access_token")
        delete("\(providerID).refresh_token")
        delete("\(providerID).expires_at")
        delete("\(providerID).scopes")
    }

    // MARK: - Configuration (client_id / api_key)

    func isConfigured(_ providerID: String) -> Bool {
        exists("\(providerID).client_id") || exists("\(providerID).api_key")
    }

    func isConnected(_ providerID: String) -> Bool {
        exists("\(providerID).access_token") || exists("\(providerID).api_key")
    }

    func getClientID(_ providerID: String) -> String? {
        getString("\(providerID).client_id")
    }

    func getClientSecret(_ providerID: String) -> String? {
        getString("\(providerID).client_secret")
    }

    func setClientID(_ providerID: String, value: String) {
        setString("\(providerID).client_id", value: value)
    }

    func setClientSecret(_ providerID: String, value: String) {
        setString("\(providerID).client_secret", value: value)
    }

    func setAPIKey(_ providerID: String, value: String) {
        setString("\(providerID).api_key", value: value)
    }

    func removeAll(_ providerID: String) {
        let suffixes = [
            ".client_id", ".client_secret",
            ".access_token", ".refresh_token", ".expires_at", ".scopes",
            ".api_key", ".secret_id", ".secret_key",
        ]
        for suffix in suffixes {
            delete("\(providerID)\(suffix)")
        }
    }

    // MARK: - Reactive state

    /// Rebuilds the published provider status array from the keychain.
    func refresh() {
        providers = Provider.all.map { provider in
            let configured = isConfigured(provider.id)
            let connected = isConnected(provider.id)
            var needsRefresh = false
            var entry: TokenEntry?

            if connected, provider.kind == .oauth2 {
                entry = getEntry(provider.id)
                needsRefresh = entry?.needsRefresh(strategy: provider.refreshStrategy) ?? false
            }

            return ProviderStatus(
                provider: provider,
                configured: configured,
                connected: connected,
                entry: entry,
                needsRefresh: needsRefresh
            )
        }
    }
}
