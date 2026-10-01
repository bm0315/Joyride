import JoyrideCore
import Foundation
@preconcurrency import Network

enum LocalHTTPServerError: LocalizedError {
    case invalidPort(UInt16)

    var errorDescription: String? {
        switch self {
        case let .invalidPort(port): "Invalid listener port: \(port)"
        }
    }
}

final class LocalHTTPServer: @unchecked Sendable {
    typealias EventHandler = @Sendable (AgentEvent, Date) -> Void
    typealias StatusHandler = @Sendable (String) -> Void

    private let queue = DispatchQueue(label: "app.joyride.http", qos: .userInitiated)
    private let decoder = JSONDecoder()
    private let eventHandler: EventHandler
    private let statusHandler: StatusHandler
    private let configurationStore: RuntimeConfigurationStore
    private let metricsStore: RuntimeMetricsStore
    private var listener: NWListener?

    init(
        eventHandler: @escaping EventHandler,
        statusHandler: @escaping StatusHandler,
        configurationStore: RuntimeConfigurationStore,
        metricsStore: RuntimeMetricsStore
    ) {
        self.eventHandler = eventHandler
        self.statusHandler = statusHandler
        self.configurationStore = configurationStore
        self.metricsStore = metricsStore
    }

    func start(port: UInt16) throws {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw LocalHTTPServerError.invalidPort(port)
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: networkPort
        )
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [statusHandler] state in
            switch state {
            case .ready:
                statusHandler("Local API ready · 127.0.0.1:\(port)")
            case let .failed(error):
                statusHandler("Local API error · \(error.localizedDescription)")
            case .cancelled:
                statusHandler("Local API stopped")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveRequest(on: connection, accumulated: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        receiveMore(on: connection, accumulated: accumulated)
    }

    private func receiveMore(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var next = accumulated
            if let data {
                next.append(data)
            }

            if next.count > 16_384 {
                send(status: 413, message: "Payload Too Large", body: ["error": "request_too_large"], on: connection)
                return
            }

            switch parseRequest(next) {
            case let .success(request):
                handle(request, on: connection)
            case .incomplete where !isComplete && error == nil:
                receiveMore(on: connection, accumulated: next)
            case let .failure(reason):
                send(status: 400, message: "Bad Request", body: ["error": reason], on: connection)
            case .incomplete:
                send(status: 400, message: "Bad Request", body: ["error": "incomplete_request"], on: connection)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        if request.method == "GET", request.path == "/health" {
            send(status: 200, message: "OK", body: ["ok": true], on: connection)
            return
        }

        if request.method == "GET", request.path == "/v1/config" {
            let config = configurationStore.snapshot()
            send(
                status: 200,
                message: "OK",
                body: [
                    "privacy_mode": config.privacyMode,
                    "keyword_blacklist": config.keywordBlacklist,
                ],
                on: connection
            )
            return
        }

        if request.method == "GET", request.path == "/v1/metrics" {
            send(status: 200, message: "OK", body: metricsStore.jsonObject(), on: connection)
            return
        }

        guard request.method == "POST", request.path == "/v1/events" else {
            send(status: 404, message: "Not Found", body: ["error": "not_found"], on: connection)
            return
        }

        do {
            let decoded = try decoder.decode(AgentEvent.self, from: request.body)
            let event = try decoded.validated()
            let receivedAt = Date()
            metricsStore.eventReceived(at: receivedAt)
            eventHandler(event, receivedAt)
            send(status: 202, message: "Accepted", body: ["accepted": true], on: connection)
        } catch let error as DecodingError {
            send(
                status: 422,
                message: "Unprocessable Content",
                body: ["error": "invalid_event", "detail": String(describing: error)],
                on: connection
            )
        } catch {
            send(
                status: 422,
                message: "Unprocessable Content",
                body: ["error": "invalid_event", "detail": error.localizedDescription],
                on: connection
            )
        }
    }

    private func send(
        status: Int,
        message: String,
        body: [String: Any],
        on connection: NWConnection
    ) {
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } catch {
            connection.cancel()
            return
        }
        let headers = [
            "HTTP/1.1 \(status) \(message)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: http://127.0.0.1",
            "",
            "",
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
}

private enum HTTPParseResult {
    case success(HTTPRequest)
    case incomplete
    case failure(String)
}

private func parseRequest(_ data: Data) -> HTTPParseResult {
    let headerMarker = Data("\r\n\r\n".utf8)
    guard let headerRange = data.range(of: headerMarker) else {
        return .incomplete
    }
    guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
        return .failure("invalid_headers")
    }

    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
        return .failure("missing_request_line")
    }
    let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard requestParts.count == 3 else {
        return .failure("invalid_request_line")
    }
    let method = String(requestParts[0])
    let path = String(requestParts[1])
    guard method == "GET" || method == "POST" else {
        return .failure("unsupported_method")
    }

    var contentLength = 0
    for line in lines.dropFirst() {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
            guard let value = Int(parts[1].trimmingCharacters(in: .whitespaces)), value >= 0, value <= 8_192 else {
                return .failure("invalid_content_length")
            }
            contentLength = value
        }
    }

    let bodyStart = headerRange.upperBound
    guard data.count >= bodyStart + contentLength else {
        return .incomplete
    }
    let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
    return .success(HTTPRequest(method: method, path: path, body: body))
}
