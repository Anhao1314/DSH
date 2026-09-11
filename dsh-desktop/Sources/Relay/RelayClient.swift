import Foundation

enum RelayError: LocalizedError, Equatable {
    case badURL
    case offline(String)
    case http(Int, String)
    case unauthorized
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "中继地址不合法"
        case .offline(let detail): return "中继没有响应（\(detail)）"
        case .http(let code, let message): return "中继返回 \(code)：\(message)"
        case .unauthorized: return "凭据已失效"
        case .decoding(let detail): return "响应解析失败：\(detail)"
        }
    }

    /// UI 用它区分「离线态」和别的错误（离线只降级显示，不弹窗）。
    var isOffline: Bool {
        if case .offline = self { return true }
        if case .http = self { return false }
        return false
    }
}

/// `/console-api/v1/*` 的极简客户端：短超时、单飞、不落盘。
/// token 只出现在内存里的 query 参数中；任何错误信息都不带 token（LogRedaction 兜底）。
final class RelayClient {
    static let base = "http://127.0.0.1:3081"

    private let session: URLSession

    init(timeout: TimeInterval = 6) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration)
    }

    // MARK: - 接口

    func health() async throws -> RelayHealth {
        try await get("/console-api/v1/health", query: [], as: RelayHealth.self)
    }

    func sessions(token: String) async throws -> SessionsResponse {
        try await get("/console-api/v1/sessions", query: [URLQueryItem(name: "token", value: token)], as: SessionsResponse.self)
    }

    func timeline(token: String, session id: String, limit: Int = 200) async throws -> TimelineResponse {
        let query = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "session", value: id),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await get("/console-api/v1/timeline", query: query, as: TimelineResponse.self)
    }

    func cancel(token: String, session id: String) async throws {
        _ = try await post("/console-api/v1/cancel", body: ["sessionId": id, "token": token])
    }

    func createSession(token: String, preset: String = "team-lead") async throws -> String {
        let data = try await post("/console-api/v1/session", body: ["agentPreset": preset, "token": token])
        let json = (try? JSONSerialization.jsonObject(with: data, options: [])) ?? nil
        let id = (json as? [String: Any])?["sessionId"] as? String ?? ""
        guard !id.isEmpty else { throw RelayError.decoding("session/create 没有返回 sessionId") }
        return id
    }

    // MARK: - 传输

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        var components = URLComponents(string: RelayClient.base + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw RelayError.badURL }
        let (data, response) = try await send(URLRequest(url: url))
        try Self.check(response, data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RelayError.decoding(String(describing: error))
        }
    }

    private func post(_ path: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: RelayClient.base + path) else { throw RelayError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        try Self.check(response, data)
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw RelayError.offline("NSURLError \(nsError.code)")
            }
            throw RelayError.offline(error.localizedDescription)
        }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw RelayError.offline("no http response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw RelayError.unauthorized }
            let json = (try? JSONSerialization.jsonObject(with: data, options: [])) ?? nil
            let message = (json as? [String: Any])?["error"] as? String ?? "http \(http.statusCode)"
            throw RelayError.http(http.statusCode, message)
        }
    }
}
