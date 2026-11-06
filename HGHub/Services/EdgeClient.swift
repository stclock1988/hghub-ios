// HGHub iOS v1 — unified edge envelope client.
// Map §3: every business call goes through one endpoint, no signing,
// no cookies, no device registration. Guest calls carry no
// Authorization header at all.

import Foundation

enum HGHubError: LocalizedError {
    case httpStatus(Int)
    case unauthorized
    case server(String)
    case invalidResponse
    case noPlayURL

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "请求失败（HTTP \(code)）"
        case .unauthorized: return "请求未授权（401）"
        case .server(let msg): return msg.isEmpty ? "接口返回失败" : msg
        case .invalidResponse: return "接口返回异常"
        case .noPlayURL: return "该集暂无可播片源"
        }
    }
}

private struct EdgeEnvelope<T: Decodable>: Decodable {
    var data: T?
    var status: Int = 0
    var msg: String?
    var req_time: Int?
}

private struct EdgeRequestBody: Encodable {
    var method: String
    var path: String
    var body: String
    var content_type: String
}

final class EdgeClient: ObservableObject {
    static let defaultBase = "https://huangguoai.com"
    static let lines = ["https://huangguoai.com", "https://huangguoai.ai"]
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private static let baseKey = "hghub.baseLine.v1"

    @Published var base: String {
        didSet { UserDefaults.standard.set(base, forKey: Self.baseKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.baseKey)
        self.base = Self.lines.contains(saved ?? "") ? saved! : Self.defaultBase
    }

    func setBase(_ url: String) {
        guard Self.lines.contains(url) else { return }
        base = url
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }

    /// One edge call. `body` is raw JSON data for the inner request
    /// (nil for GET); it is base64-encoded into the envelope, exactly
    /// as the Rust client does (map §3).
    func edge<T: Decodable>(method: String, path: String, body: Data? = nil) async throws -> T {
        let envelope = EdgeRequestBody(
            method: method,
            path: path,
            body: body.map { $0.base64EncodedString() } ?? "",
            content_type: body == nil ? "" : "application/json"
        )
        let requestData = try JSONEncoder().encode(envelope)
        let url = URL(string: base + "/api/edge/request")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(base + "/", forHTTPHeaderField: "Referer")
        // Guest: no Authorization header.

        var lastError: Error = HGHubError.invalidResponse
        // Retry up to 3 attempts, 350 ms / 700 ms backoff (map §3:
        // the site has occasional TLS flakiness).
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session().data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw HGHubError.invalidResponse
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw HGHubError.unauthorized
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw HGHubError.httpStatus(http.statusCode)
                }
                if data.isEmpty {
                    throw HGHubError.invalidResponse
                }
                let decoded = try JSONDecoder().decode(EdgeEnvelope<T>.self, from: data)
                guard decoded.status == 1, let value = decoded.data else {
                    throw HGHubError.server(decoded.msg ?? "")
                }
                return value
            } catch let error as HGHubError {
                // Business / auth errors are final — do not retry them.
                throw error
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt == 0 ? 350_000_000 : 700_000_000))
                    continue
                }
                throw lastError
            }
        }
        throw lastError
    }
}
