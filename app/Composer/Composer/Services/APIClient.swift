import Foundation

struct HealthResponse: Decodable {
    let status: String
    let version: String
    let schemaVersion: Int
    let authEnabled: Bool
    let ingestAuthEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case schemaVersion = "schema_version"
        case authEnabled = "auth_enabled"
        case ingestAuthEnabled = "ingest_auth_enabled"
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case http(status: Int, body: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .decoding(let err):
            return "Decoding error: \(err.localizedDescription)"
        case .transport(let err):
            return err.localizedDescription
        }
    }
}

final class APIClient {
    var baseURL: URL
    var apiKey: String?
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:5006")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Health

    func health() async throws -> HealthResponse {
        try await request("/v1/health", auth: false)
    }

    // MARK: - Items

    func listItems(
        query: String? = nil,
        archived: Bool? = false,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> ItemListResponse {
        var qs: [String] = []
        if let query, !query.isEmpty {
            qs.append("q=\(urlEncode(query))")
        }
        if let archived {
            qs.append("archived=\(archived)")
        }
        if let limit { qs.append("limit=\(limit)") }
        if let offset { qs.append("offset=\(offset)") }
        let path = "/items" + (qs.isEmpty ? "" : "?\(qs.joined(separator: "&"))")
        return try await request(path)
    }

    func getItem(id: String) async throws -> Item {
        try await request("/items/\(id)")
    }

    func setItemArchived(id: String, archived: Bool) async throws -> Item {
        let body = try JSONSerialization.data(withJSONObject: ["archived": archived])
        return try await request("/items/\(id)", method: "PATCH", body: body)
    }

    func deleteItem(id: String) async throws {
        let _: EmptyResponse = try await request("/items/\(id)", method: "DELETE", allow204: true)
    }

    // MARK: - Core

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        auth: Bool = true,
        allow204: Bool = false
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let key = apiKey, !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: body)
        }

        if allow204 && (http.statusCode == 204 || data.isEmpty) {
            return EmptyResponse() as! T
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

struct EmptyResponse: Decodable {}
