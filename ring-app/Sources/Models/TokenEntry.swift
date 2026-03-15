import Foundation

/// Holds the OAuth2 token state for a provider, mirroring the Go CLI keychain keys.
struct TokenEntry {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date?
    var scopes: [String]

    private static let proactiveRefreshWindow: TimeInterval = 5 * 60 // 5 minutes

    /// True if the access token has already expired.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date.now >= expiresAt
    }

    /// True if the token should be refreshed proactively (within 5 min of expiry).
    var needsProactiveRefresh: Bool {
        guard let expiresAt else { return false }
        return Date.now.addingTimeInterval(Self.proactiveRefreshWindow) >= expiresAt
    }

    /// Returns true when a refresh is required given the provider's strategy.
    func needsRefresh(strategy: RefreshStrategy) -> Bool {
        switch strategy {
        case .never:      return false
        case .onExpiry:   return isExpired
        case .proactive:  return needsProactiveRefresh
        }
    }
}
