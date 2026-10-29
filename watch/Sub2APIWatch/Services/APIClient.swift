import Foundation
import Darwin

enum BridgeError: LocalizedError {
    case configuration, address, keyRequired, unauthorized, missing, unavailable, invalidResponse

    var errorDescription: String? {
        switch self {
        case .configuration: return "请先设置服务地址和访问密钥。"
        case .address: return "请输入有效的 IP:端口、HTTP 或 HTTPS 地址。"
        case .keyRequired: return "请输入查询服务的访问密钥。"
        case .unauthorized: return "访问密钥无效，请检查连接设置。"
        case .missing: return "用户或 Key 已不存在，请重新选择。"
        case .unavailable: return "暂时无法连接，请稍后重试。"
        case .invalidResponse: return "服务返回的数据无法读取。"
        }
    }
}

// Do not forward a query credential through a server redirect.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct APIClient {
    let baseURL: URL
    let key: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static func address(_ text: String) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.contains("://")
        guard !text.isEmpty,
              text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var components = URLComponents(string: hasScheme ? text : "https://" + text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw BridgeError.address
        }
        components.scheme = !hasScheme && isIPAddress(host) ? "http" : scheme
        guard let url = components.url else { throw BridgeError.address }
        return url
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return host.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw BridgeError.address
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BridgeError.address }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw BridgeError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 401, 403: throw BridgeError.unauthorized
            case 404: throw BridgeError.missing
            default: throw BridgeError.unavailable
            }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw BridgeError.invalidResponse }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw BridgeError.unavailable
        }
    }

    func users() async throws -> [WatchUser] {
        struct Response: Decodable { let users: [WatchUser] }
        let response: Response = try await get("users")
        return response.users
    }

    func keys(userID: Int) async throws -> [WatchKey] {
        struct Response: Decodable { let keys: [WatchKey] }
        let response: Response = try await get("users/\(userID)/keys")
        return response.keys
    }

    func accounts() async throws -> AccountsResponse { try await get("accounts") }

    func today(scope: UsageScope) async throws -> DailyUsage {
        var query: [URLQueryItem] = []
        if let id = scope.userID { query.append(URLQueryItem(name: "userId", value: String(id))) }
        if let id = scope.keyID { query.append(URLQueryItem(name: "apiKeyId", value: String(id))) }
        return try await get("usage/today", query: query)
    }
}
