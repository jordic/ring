import Foundation
import Network

/// Servidor HTTP temporal que escolta al port 9876 i captura el codi OAuth2.
/// Usat per providers que no accepten URL schemes personalitzats (ex: Google Desktop).
/// Es tanca automàticament en rebre la primera petició.
final class LocalCallbackServer: @unchecked Sendable {

    static let port: UInt16 = 9876
    static let callbackURL = "http://localhost:9876/callback"

    private var listener: NWListener?
    private var continuation: CheckedContinuation<CallbackResult, Error>?
    private let queue = DispatchQueue(label: "com.ring.callback-server")

    struct CallbackResult {
        let code: String
        let state: String
    }

    deinit {
        stop()
    }

    /// Inicia el servidor i espera fins que arriba el callback OAuth2.
    /// Es tanca sol en rebre la resposta.
    func waitForCallback() async throws -> CallbackResult {
        // Assegurem que no hi ha cap listener anterior
        stop()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true

                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .failed(let error):
                        self?.fail(ServerError.listenerFailed(error.localizedDescription))
                    case .cancelled:
                        // Si es cancel·la sense haver resolt, fallem
                        self?.fail(ServerError.listenerFailed("Server cancelled"))
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }

                listener.start(queue: queue)
            } catch {
                continuation.resume(throwing: ServerError.listenerFailed(error.localizedDescription))
                self.continuation = nil
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Private

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }

            // Ignorem favicon requests i altres paths que no siguin /callback
            guard request.contains("/callback?") || request.contains("/callback HTTP") else {
                let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let result = self.parseRequest(request)
            let html: String
            if result != nil {
                html = "<html><body style='font-family:system-ui;padding:40px;text-align:center'><h2>Authorized!</h2><p>You can close this window and return to Ring.</p></body></html>"
            } else {
                html = "<html><body style='font-family:system-ui;padding:40px;text-align:center'><h2>Authorization failed</h2><p>Missing code parameter.</p></body></html>"
            }

            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            // Donem un moment perquè la resposta arribi al browser
            self.queue.asyncAfter(deadline: .now() + 0.2) {
                self.stop()
            }

            if let result {
                self.succeed(result)
            } else {
                self.fail(ServerError.missingCode)
            }
        }
    }

    private func parseRequest(_ raw: String) -> CallbackResult? {
        // First line: GET /callback?code=xxx&state=yyy HTTP/1.1
        guard let firstLine = raw.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost" + pathPart),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else { return nil }

        return CallbackResult(code: code, state: state)
    }

    private func succeed(_ result: CallbackResult) {
        let c = continuation
        continuation = nil
        c?.resume(returning: result)
    }

    private func fail(_ error: Error) {
        let c = continuation
        continuation = nil
        c?.resume(throwing: error)
    }

    enum ServerError: LocalizedError {
        case listenerFailed(String)
        case missingCode

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let msg): return "Callback server failed: \(msg)"
            case .missingCode:             return "OAuth callback did not include an authorization code"
            }
        }
    }
}
