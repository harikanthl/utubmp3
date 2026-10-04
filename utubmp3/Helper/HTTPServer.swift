//
//  HTTPServer.swift
//  utubmp3
//
//  A minimal HTTP/1.1 JSON server bound to 127.0.0.1 (one request per connection).
//

import Foundation
import Network

nonisolated struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]  // lowercased names
    let body: Data

    var jsonBody: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }
}

nonisolated struct HTTPResponse {
    var status: Int
    var json: [String: Any]
}

nonisolated final class HTTPServer: @unchecked Sendable {
    private static let maxRequestSize = 64 * 1024
    private let listener: NWListener
    private let handler: (HTTPRequest) -> HTTPResponse
    private let queue = DispatchQueue(label: "utubmp3.http")

    init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffer: Data())
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                helperLog("listener failed: \(error)")
                exit(1)  // launchd restarts us
            }
        }
        listener.start(queue: queue)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = Self.parse(buffer) {
                // Handlers may run ffmpeg for a while; keep the listener queue free.
                DispatchQueue.global().async {
                    let response = request.method == "OPTIONS"
                        ? HTTPResponse(status: 204, json: [:])
                        : self.handler(request)
                    self.send(response, for: request, on: connection)
                }
            } else if error != nil || isComplete || buffer.count > Self.maxRequestSize {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// Returns a request once the headers and the full Content-Length body have arrived.
    private static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[headerEnd.upperBound...]
        guard body.count >= length else { return nil }

        let components = URLComponents(string: String(requestLine[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(method: String(requestLine[0]),
                           path: components?.path ?? "/",
                           query: query,
                           headers: headers,
                           body: Data(body.prefix(length)))
    }

    private func send(_ response: HTTPResponse, for request: HTTPRequest, on connection: NWConnection) {
        let body = response.status == 204 ? Data() : ((try? JSONSerialization.data(withJSONObject: response.json)) ?? Data())
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        // Only the extension (non-http origin) gets CORS access; web pages are refused upstream.
        if let origin = request.headers["origin"], !HelperServer.isWebOrigin(origin) {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Access-Control-Allow-Methods: GET, POST\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
        }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 415: return "Unsupported Media Type"
        default: return "Error"
        }
    }
}
