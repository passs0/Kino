import Foundation
import Network

/// Embedded HTTP 1.1 server utilizing Network.framework (NWListener) to stream HLS and media chunks locally to AVPlayer.
public final class LocalStreamingServer: @unchecked Sendable {
    private var listener: NWListener?
    private var baseDirectory: URL?
    private let queue = DispatchQueue(label: "kino.local.http.server", qos: .userInitiated)
    private var activePort: UInt16 = 0
    private var activeConnections: [NWConnection] = []
    private let connectionsLock = NSLock()

    public init() {}

    public var serverURL: URL? {
        guard activePort > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(activePort)")
    }

    /// Starts serving files from the specified local directory.
    public func start(serving directory: URL) throws -> URL {
        stop()

        self.baseDirectory = directory
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        let newListener = try NWListener(using: parameters)
        self.listener = newListener

        let semaphore = DispatchSemaphore(value: 0)

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if let port = newListener.port?.rawValue {
                    self.activePort = port
                }
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 2.0)

        guard activePort > 0 else {
            throw NSError(domain: "LocalStreamingServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind local HTTP streaming port."])
        }

        return URL(string: "http://127.0.0.1:\(activePort)")!
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        activePort = 0
        baseDirectory = nil
        connectionsLock.lock()
        let conns = activeConnections
        activeConnections.removeAll()
        connectionsLock.unlock()
        for conn in conns {
            conn.cancel()
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        activeConnections.append(connection)
        connectionsLock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if state == .cancelled {
                if let c = connection {
                    self?.connectionsLock.lock()
                    self?.activeConnections.removeAll(where: { $0 === c })
                    self?.connectionsLock.unlock()
                }
            }
        }
        connection.start(queue: queue)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, error == nil else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            self.respond(to: requestString, on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        guard let base = baseDirectory else {
            sendResponse(connection: connection, statusCode: 500, statusText: "Internal Error", headers: [:], body: Data())
            return
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            connection.cancel()
            return
        }

        let parts = firstLine.split(separator: " ")
        let method = String(parts.first ?? "")
        guard parts.count >= 2, method == "GET" || method == "HEAD" else {
            sendResponse(connection: connection, statusCode: 405, statusText: "Method Not Allowed", headers: [:], body: Data())
            return
        }

        var path = String(parts[1])
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[..<queryIndex])
        }
        let cleanRelative = (path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent
        let fileURL = cleanRelative.isEmpty ? base.appendingPathComponent("playlist.m3u8") : base.appendingPathComponent(cleanRelative)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sendResponse(connection: connection, statusCode: 404, statusText: "Not Found", headers: ["Content-Length": "0"], body: Data())
            return
        }

        // Determine MIME
        let ext = fileURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "m3u8": mime = "application/vnd.apple.mpegurl"
        case "ts": mime = "video/mp2t"
        case "mp4": mime = "video/mp4"
        case "m4s": mime = "video/iso.segment"
        default: mime = "application/octet-stream"
        }

        do {
            let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let headers: [String: String] = [
                "Content-Type": mime,
                "Content-Length": "\(fileData.count)",
                "Access-Control-Allow-Origin": "*",
                "Accept-Ranges": "bytes",
                "Cache-Control": ext == "m3u8" ? "no-cache, no-store" : "public, max-age=3600",
                "Connection": "close"
            ]
            let body = (method == "HEAD") ? Data() : fileData
            sendResponse(connection: connection, statusCode: 200, statusText: "OK", headers: headers, body: body)
        } catch {
            sendResponse(connection: connection, statusCode: 500, statusText: "Read Error", headers: [:], body: Data())
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, statusText: String, headers: [String: String], body: Data) {
        var headerString = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (k, v) in headers {
            headerString += "\(k): \(v)\r\n"
        }
        headerString += "\r\n"

        var responseData = headerString.data(using: .utf8) ?? Data()
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
