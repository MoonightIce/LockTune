import Foundation
import Network

public actor LoopbackOAuthServer {
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackURL: URL?
    private var startupError: Error?
    private var isCancelled = false

    public init() {}

    public func start() async throws -> URL {
        if let listener, let port = listener.port {
            return URL(string: "http://127.0.0.1:\(port.rawValue)/callback")!
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener.start(queue: DispatchQueue(label: "app.locktune.oauth-loopback"))
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    public func waitForCallback() async throws -> URL {
        if let callbackURL { return callbackURL }
        if let startupError { throw startupError }
        if isCancelled { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public func cancel() {
        isCancelled = true
        let error = CancellationError()
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
        stop()
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let listener, let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/callback")
            else { return }
            readyContinuation?.resume(returning: url)
            readyContinuation = nil
        case let .failed(error):
            startupError = error
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
            callbackContinuation?.resume(throwing: error)
            callbackContinuation = nil
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "app.locktune.oauth-callback"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            Task { await self?.receive(data: data, error: error, from: connection) }
        }
    }

    private func receive(data: Data?, error: NWError?, from connection: NWConnection) {
        guard error == nil,
              let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.split(separator: "\r\n", maxSplits: 1).first,
              requestLine.hasPrefix("GET "),
              let target = requestLine.split(separator: " ").dropFirst().first,
              let listener,
              let port = listener.port,
              let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(target)")
        else {
            respond(connection, status: "400 Bad Request", message: "LockTune could not read the authorization response.")
            return
        }

        callbackURL = url
        callbackContinuation?.resume(returning: url)
        callbackContinuation = nil
        respond(connection, status: "200 OK", message: "Authorization complete. You can close this window and return to LockTune.")
        stop()
    }

    private func respond(_ connection: NWConnection, status: String, message: String) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>LockTune</title></head>
        <body style="font: -apple-system-body; max-width: 38rem; margin: 4rem auto; padding: 1rem">
        <h1>LockTune</h1><p>\(message)</p></body></html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
