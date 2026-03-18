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

/// Reads and writes the macOS Keychain using a single JSON blob,
/// sharing the same service name as the Go CLI.
@MainActor
final class KeychainStore: ObservableObject {

    // MUST match `const Service = "com.ring.tokenstore"` in the Go CLI
    static let service = "com.ring.tokenstore"
    static let storeAccount = "data"

    @Published var providers: [ProviderStatus] = []

    /// In-memory cache of all key-value pairs.
    private var store: [String: String] = [:]

    init() {
        loadFromKeychain()
        migrateOldFormat()
        refresh()
    }

    // MARK: - Single-blob Keychain I/O

    private func loadFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      Self.service,
            kSecAttrAccount:      Self.storeAccount,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            store = [:]
            return
        }
        store = dict
    }

    private func saveToKeychain() {
        guard let data = try? JSONEncoder().encode(store) else { return }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.storeAccount,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - Migration from old per-key format

    private func migrateOldFormat() {
        guard store.isEmpty else { return }

        let suffixes = [
            ".client_id", ".client_secret",
            ".access_token", ".refresh_token", ".expires_at", ".scopes",
            ".api_key", ".secret_id", ".secret_key",
        ]

        var migrated = false
        var oldKeys: [String] = []

        for provider in Provider.all {
            for suffix in suffixes {
                let key = "\(provider.id)\(suffix)"
                if let value = readOldItem(key) {
                    store[key] = value
                    oldKeys.append(key)
                    migrated = true
                }
            }
        }

        // Migrate credentials.list and credential entries
        if let list = readOldItem("credentials.list") {
            store["credentials.list"] = list
            oldKeys.append("credentials.list")
            migrated = true
            let credSuffixes = [".username", ".password", ".totp_secret", ".session_path"]
            for id in list.split(separator: ",").map(String.init) where !id.isEmpty {
                for suffix in credSuffixes {
                    let key = "\(id)\(suffix)"
                    if let value = readOldItem(key) {
                        store[key] = value
                        oldKeys.append(key)
                    }
                }
            }
        }

        if migrated {
            saveToKeychain()
            for key in oldKeys {
                deleteOldItem(key)
            }
        }
    }

    private func readOldItem(_ account: String) -> String? {
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

    private func deleteOldItem(_ account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Key-value accessors (same API as before)

    func getString(_ account: String) -> String? {
        store[account]
    }

    func setString(_ account: String, value: String) {
        store[account] = value
        saveToKeychain()
    }

    func delete(_ account: String) {
        store.removeValue(forKey: account)
        saveToKeychain()
    }

    func exists(_ account: String) -> Bool {
        store[account] != nil
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
        store["\(providerID).access_token"] = entry.accessToken
        if !entry.refreshToken.isEmpty {
            store["\(providerID).refresh_token"] = entry.refreshToken
        }
        if let expiresAt = entry.expiresAt {
            store["\(providerID).expires_at"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        if !entry.scopes.isEmpty {
            store["\(providerID).scopes"] = entry.scopes.joined(separator: ",")
        }
        saveToKeychain()
    }

    func clearTokens(_ providerID: String) {
        store.removeValue(forKey: "\(providerID).access_token")
        store.removeValue(forKey: "\(providerID).refresh_token")
        store.removeValue(forKey: "\(providerID).expires_at")
        store.removeValue(forKey: "\(providerID).scopes")
        saveToKeychain()
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
            store.removeValue(forKey: "\(providerID)\(suffix)")
        }
        saveToKeychain()
    }

    // MARK: - Reactive state

    /// Rebuilds the published provider status array from the in-memory store.
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
