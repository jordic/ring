import Foundation
import AuthenticationServices
import CryptoKit

/// Handles OAuth2 flows.
/// - Providers amb `usesLocalhostCallback` (Google): obren el browser + servidor local al port 9876
/// - Resta: ASWebAuthenticationSession amb URL scheme `ring://`
@MainActor
final class OAuthFlow: NSObject {

    static let callbackScheme = "ring"
    static let callbackURL = "ring://oauth/callback"

    // MARK: - Public API

    /// Performs the full OAuth2 login flow.
    func login(provider: Provider, clientID: String, clientSecret: String, scopes: [String]) async throws -> TokenEntry {
        let allScopes = mergeScopes(provider.defaultScopes, scopes)

        if provider.useDeviceFlow {
            throw OAuthError.deviceFlowNotSupported
        }

        return try await authorizationCodeFlow(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: allScopes
        )
    }

    /// Re-authenticates with the union of existing and new scopes.
    func addScopes(provider: Provider, clientID: String, clientSecret: String, currentScopes: [String], newScopes: [String]) async throws -> TokenEntry {
        let merged = mergeScopes(currentScopes, newScopes)
        return try await authorizationCodeFlow(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: merged
        )
    }

    /// Exchanges a refresh token for a new access token.
    func refresh(provider: Provider, refreshToken: String, clientID: String, clientSecret: String) async throws -> TokenEntry {
        var params = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     clientID,
        ]
        if !clientSecret.isEmpty {
            params["client_secret"] = clientSecret
        }

        return try await exchangeToken(tokenURL: provider.tokenURL, params: params, existingScopes: nil)
    }

    /// Builds the authorization URL for a provider (for manual "Open in browser" flow).
    func buildAuthURL(provider: Provider, clientID: String, scopes: [String]) throws -> (url: URL, state: String, verifier: String?) {
        let allScopes = mergeScopes(provider.defaultScopes, scopes)
        let state = try generateState()
        let redirectURI = provider.usesLocalhostCallback ? LocalCallbackServer.callbackURL : Self.callbackURL

        var components = URLComponents(string: provider.authURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "state",         value: state),
        ]

        if !allScopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: allScopes.joined(separator: " ")))
        }

        var verifier: String?
        if provider.usePKCE {
            verifier = try generateVerifier()
            queryItems.append(URLQueryItem(name: "code_challenge", value: generateChallenge(from: verifier!)))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }

        // Google: access_type=offline per obtenir refresh_token
        if provider.id == "google" {
            queryItems.append(URLQueryItem(name: "access_type", value: "offline"))
            queryItems.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw OAuthError.invalidURL
        }

        return (url, state, verifier)
    }

    /// Waits for the OAuth callback via localhost server, then exchanges the code.
    func waitForLocalhostCallback(provider: Provider, clientID: String, clientSecret: String, state: String, verifier: String?, scopes: [String]) async throws -> TokenEntry {
        let server = LocalCallbackServer()

        let result = try await server.waitForCallback()

        guard result.state == state else {
            throw OAuthError.stateMismatch
        }

        return try await exchangeCode(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            code: result.code,
            verifier: verifier,
            scopes: scopes
        )
    }

    // MARK: - Authorization Code Flow (automatic)

    private func authorizationCodeFlow(provider: Provider, clientID: String, clientSecret: String, scopes: [String]) async throws -> TokenEntry {
        let redirectURI = provider.usesLocalhostCallback ? LocalCallbackServer.callbackURL : Self.callbackURL
        let state = try generateState()

        var components = URLComponents(string: provider.authURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "state",         value: state),
        ]

        if !scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }

        var verifier: String?
        if provider.usePKCE {
            verifier = try generateVerifier()
            queryItems.append(URLQueryItem(name: "code_challenge", value: generateChallenge(from: verifier!)))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }

        if provider.id == "google" {
            queryItems.append(URLQueryItem(name: "access_type", value: "offline"))
            queryItems.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        components.queryItems = queryItems
        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        let code: String
        if provider.usesLocalhostCallback {
            code = try await localhostFlow(authURL: authURL, expectedState: state)
        } else {
            let callbackURL = try await startSession(url: authURL)
            code = try extractCode(from: callbackURL, expectedState: state)
        }

        return try await exchangeCode(
            provider: provider,
            clientID: clientID,
            clientSecret: clientSecret,
            code: code,
            verifier: verifier,
            scopes: scopes
        )
    }

    // MARK: - Localhost server flow (Google Desktop i similars)

    private func localhostFlow(authURL: URL, expectedState: String) async throws -> String {
        let server = LocalCallbackServer()

        async let callbackResult = server.waitForCallback()
        NSWorkspace.shared.open(authURL)

        let result = try await callbackResult

        guard result.state == expectedState else {
            throw OAuthError.stateMismatch
        }
        return result.code
    }

    // MARK: - ASWebAuthenticationSession

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: OAuthError.sessionFailed(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.noCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            session.start()

            objc_setAssociatedObject(self, Unmanaged.passRetained(session).toOpaque(), session, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(provider: Provider, clientID: String, clientSecret: String, code: String, verifier: String?, scopes: [String]) async throws -> TokenEntry {
        let redirectURI = provider.usesLocalhostCallback ? LocalCallbackServer.callbackURL : Self.callbackURL

        var params: [String: String] = [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": redirectURI,
            "client_id":    clientID,
        ]
        if !clientSecret.isEmpty {
            params["client_secret"] = clientSecret
        }
        if let verifier {
            params["code_verifier"] = verifier
        }

        return try await exchangeToken(tokenURL: provider.tokenURL, params: params, existingScopes: scopes)
    }

    private func exchangeToken(tokenURL: String, params: [String: String], existingScopes: [String]?) async throws -> TokenEntry {
        guard let url = URL(string: tokenURL) else { throw OAuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = params.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let errMsg = json["error"] as? String {
            let desc = json["error_description"] as? String ?? errMsg
            throw OAuthError.tokenError(desc)
        }

        guard http.statusCode == 200,
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenError("HTTP \(http.statusCode): missing access_token")
        }

        let refreshToken = json["refresh_token"] as? String ?? ""
        var expiresAt: Date?
        if let expiresIn = json["expires_in"] as? TimeInterval {
            expiresAt = Date().addingTimeInterval(expiresIn)
        }

        let scopeStr = json["scope"] as? String
        let scopes: [String]
        if let scopeStr, !scopeStr.isEmpty {
            scopes = scopeStr.components(separatedBy: " ")
        } else {
            scopes = existingScopes ?? []
        }

        return TokenEntry(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes
        )
    }

    // MARK: - Helpers

    private func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallback
        }
        let items = components.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw OAuthError.sessionFailed(error)
        }

        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw OAuthError.stateMismatch
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.invalidCallback
        }
        return code
    }

    private func generateVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw OAuthError.randomFailed }
        return Data(bytes).base64URLEncoded()
    }

    private func generateChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }

    private func generateState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw OAuthError.randomFailed }
        return Data(bytes).base64URLEncoded()
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func mergeScopes(_ existing: [String], _ new: [String]) -> [String] {
        var seen = Set<String>()
        return (existing + new).filter { seen.insert($0).inserted }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthFlow: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case deviceFlowNotSupported
    case invalidURL
    case invalidCallback
    case invalidResponse
    case noCallback
    case stateMismatch
    case randomFailed
    case sessionFailed(String)
    case tokenError(String)

    var errorDescription: String? {
        switch self {
        case .deviceFlowNotSupported: return "Device flow is only supported in the CLI (ring login github)"
        case .invalidURL:             return "Invalid authorization URL"
        case .invalidCallback:        return "Invalid OAuth callback"
        case .invalidResponse:        return "Invalid server response"
        case .noCallback:             return "No callback URL received"
        case .stateMismatch:          return "State mismatch — possible CSRF attack"
        case .randomFailed:           return "Failed to generate random bytes"
        case .sessionFailed(let msg): return "Authorization failed: \(msg)"
        case .tokenError(let msg):    return "Token error: \(msg)"
        }
    }
}

// MARK: - Data extension

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
