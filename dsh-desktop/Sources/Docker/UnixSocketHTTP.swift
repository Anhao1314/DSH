import Foundation
import Network

struct UnixSocketHTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    var bodyText: String { String(data: body, encoding: .utf8) ?? "" }
}

enum UnixSocketHTTPError: LocalizedError {
    case connectFailed(String)
    case timeout
    case sendFailed(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .connectFailed(let detail): return "unix socket 连接失败：\(detail)"
        case .timeout: return "unix socket 请求超时"
        case .sendFailed(let detail): return "unix socket 发送失败：\(detail)"
        case .badResponse(let detail): return "unix socket 响应异常：\(detail)"
        }
    }
}

/// 极简 HTTP/1.1 over unix domain socket（Network.framework 手写）。
/// 只支持本项目的用法：GET/POST、请求短小、`Connection: close` 读完即断。
/// 同步阻塞，必须在后台队列调用。
enum UnixSocketHTTP {
    static func request(
        socketPath: String,
        method: String = "GET",
        path: String,
        body: Data? = nil,
        timeout: TimeInterval = 8
    ) throws -> UnixSocketHTTPResponse {
        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        let queue = DispatchQueue(label: "local.dsh.unixhttp")
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()

        var finished = false
        var response: UnixSocketHTTPResponse?
        var failure: Error?
        var buffer = Data()

        func finish(_ value: UnixSocketHTTPResponse?, _ error: Error?) {
            lock.lock()
            if !finished {
                finished = true
                response = value
                failure = error
                semaphore.signal()
            }
            lock.unlock()
        }

        func parseBuffer() {
            do {
                finish(try parse(buffer), nil)
            } catch {
                finish(nil, error)
            }
        }

        func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
                if let data, !data.isEmpty { buffer.append(data) }
                if let error {
                    finish(nil, UnixSocketHTTPError.connectFailed(error.localizedDescription))
                    connection.cancel()
                    return
                }
                if isComplete {
                    parseBuffer()
                    connection.cancel()
                    return
                }
                receiveLoop()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var head = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n"
                if let body {
                    head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
                }
                var request = Data(head.utf8)
                request.append(Data("\r\n".utf8))
                if let body { request.append(body) }
                connection.send(content: request, completion: .contentProcessed { error in
                    if let error {
                        finish(nil, UnixSocketHTTPError.sendFailed(error.localizedDescription))
                        connection.cancel()
                        return
                    }
                    receiveLoop()
                })
            case .failed(let error):
                finish(nil, UnixSocketHTTPError.connectFailed(error.localizedDescription))
            case .cancelled:
                finish(nil, UnixSocketHTTPError.connectFailed("连接被取消"))
            default:
                break
            }
        }

        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) {
            finish(nil, UnixSocketHTTPError.timeout)
            connection.cancel()
        }

        if semaphore.wait(timeout: .now() + timeout + 2) == .timedOut {
            connection.cancel()
            throw UnixSocketHTTPError.timeout
        }
        if let failure { throw failure }
        guard let response else { throw UnixSocketHTTPError.badResponse("空响应") }
        return response
    }

    // MARK: - 解析

    private static func parse(_ data: Data) throws -> UnixSocketHTTPResponse {
        let separator = Data([13, 10, 13, 10]) // \r\n\r\n
        guard let range = data.range(of: separator) else {
            throw UnixSocketHTTPError.badResponse("缺少响应头分隔符")
        }
        let headData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else {
            throw UnixSocketHTTPError.badResponse("响应头不是 UTF-8")
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw UnixSocketHTTPError.badResponse("缺少状态行") }
        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            throw UnixSocketHTTPError.badResponse("状态行无法解析")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var body = data.subdata(in: range.upperBound..<data.endIndex)
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = dechunk(body)
        } else if let lengthText = headers["content-length"], let length = Int(lengthText), body.count > length {
            body = body.prefix(length)
        }
        return UnixSocketHTTPResponse(status: status, headers: headers, body: body)
    }

    /// 解开 Transfer-Encoding: chunked（没有完整块时返回已解出的部分）。
    static func dechunk(_ data: Data) -> Data {
        var out = Data()
        var index = data.startIndex
        while index < data.endIndex {
            guard let lineEnd = data.range(of: Data([13, 10]), in: index..<data.endIndex) else { break }
            let sizeText = String(data: data[index..<lineEnd.lowerBound], encoding: .utf8)?
                .split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { break }
            if size == 0 { break }
            let start = lineEnd.upperBound
            guard let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) else { break }
            out.append(data[start..<end])
            guard let next = data.index(end, offsetBy: 2, limitedBy: data.endIndex) else { break }
            index = next
        }
        return out
    }

    /// Docker `/logs` 的多路复用帧：8 字节头（stream 1B + 3B 保留 + 大端长度 4B）+ 载荷。
    /// 非多路复用流（TTY）原样返回文本。
    static func demuxFrames(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var out = Data()
        var index = 0
        var sawFrame = false
        while index + 8 <= bytes.count {
            let stream = bytes[index]
            let length = (Int(bytes[index + 4]) << 24) | (Int(bytes[index + 5]) << 16)
                | (Int(bytes[index + 6]) << 8) | Int(bytes[index + 7])
            guard (stream == 1 || stream == 2),
                  bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 0,
                  length >= 0, index + 8 + length <= bytes.count else { break }
            out.append(contentsOf: bytes[(index + 8)..<(index + 8 + length)])
            index += 8 + length
            sawFrame = true
        }
        guard sawFrame else { return String(data: data, encoding: .utf8) ?? "" }
        return String(data: out, encoding: .utf8) ?? ""
    }
}
