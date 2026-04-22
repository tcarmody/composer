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

    func refreshItem(id: String) async throws -> Item {
        let body = try JSONSerialization.data(withJSONObject: [String: Any]())
        return try await request("/items/\(id)/refresh", method: "POST", body: body)
    }

    // MARK: - Notes

    func listNotes(limit: Int = 100, offset: Int = 0) async throws -> NoteListResponse {
        try await request("/notes?limit=\(limit)&offset=\(offset)")
    }

    func getNote(id: String) async throws -> Note {
        try await request("/notes/\(id)")
    }

    func createNote(title: String? = nil, body: String = "") async throws -> Note {
        var payload: [String: Any] = ["body": body]
        if let title { payload["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/notes", method: "POST", body: data)
    }

    func patchNote(id: String, title: String?? = nil, body: String? = nil) async throws -> Note {
        var payload: [String: Any] = [:]
        if case .some(let value) = title {
            payload["title"] = value ?? NSNull()
        }
        if let body { payload["body"] = body }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/notes/\(id)", method: "PATCH", body: data)
    }

    func deleteNote(id: String) async throws {
        let _: EmptyResponse = try await request("/notes/\(id)", method: "DELETE", allow204: true)
    }

    // MARK: - Drafts

    func listDrafts(limit: Int = 100, offset: Int = 0) async throws -> DraftListResponse {
        try await request("/drafts?limit=\(limit)&offset=\(offset)")
    }

    func getDraft(id: String) async throws -> Draft {
        try await request("/drafts/\(id)")
    }

    func createDraft(
        title: String? = nil,
        body: String = "",
        status: DraftStatus = .wip
    ) async throws -> Draft {
        var payload: [String: Any] = ["body": body, "status": status.rawValue]
        if let title { payload["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/drafts", method: "POST", body: data)
    }

    func patchDraft(
        id: String,
        title: String?? = nil,
        body: String? = nil,
        status: DraftStatus? = nil
    ) async throws -> Draft {
        var payload: [String: Any] = [:]
        if case .some(let value) = title {
            payload["title"] = value ?? NSNull()
        }
        if let body { payload["body"] = body }
        if let status { payload["status"] = status.rawValue }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/drafts/\(id)", method: "PATCH", body: data)
    }

    func deleteDraft(id: String) async throws {
        let _: EmptyResponse = try await request("/drafts/\(id)", method: "DELETE", allow204: true)
    }

    func assistDraft(
        id: String,
        action: DraftAssistAction,
        selection: String? = nil,
        instructions: String? = nil
    ) async throws -> DraftAssistResponse {
        var payload: [String: Any] = ["action": action.rawValue]
        if let selection, !selection.isEmpty { payload["selection"] = selection }
        if let instructions, !instructions.isEmpty {
            payload["instructions"] = instructions
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/drafts/\(id)/assist", method: "POST", body: data)
    }

    // MARK: - Collections

    func listCollections() async throws -> [Collection] {
        try await request("/collections")
    }

    func createCollection(name: String, description: String? = nil) async throws -> Collection {
        var body: [String: Any] = ["name": name]
        if let description { body["description"] = description }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await request("/collections", method: "POST", body: data)
    }

    func getCollection(id: String) async throws -> Outline {
        try await request("/collections/\(id)")
    }

    func deleteCollection(id: String) async throws {
        let _: EmptyResponse = try await request("/collections/\(id)", method: "DELETE", allow204: true)
    }

    func addCollectionMember(id: String, memberType: MemberType, memberId: String) async throws -> Outline {
        let body = try JSONSerialization.data(withJSONObject: [
            "member_type": memberType.rawValue,
            "member_id": memberId
        ])
        return try await request("/collections/\(id)/members", method: "POST", body: body)
    }

    func removeCollectionMember(id: String, memberType: MemberType, memberId: String) async throws {
        let path = "/collections/\(id)/members/\(memberType.rawValue)/\(memberId)"
        let _: EmptyResponse = try await request(path, method: "DELETE", allow204: true)
    }

    func reorderCollection(id: String, members: [(MemberType, String)]) async throws -> Outline {
        let serialized = members.map { [$0.0.rawValue, $0.1] }
        let body = try JSONSerialization.data(withJSONObject: ["members": serialized])
        return try await request("/collections/\(id)/reorder", method: "POST", body: body)
    }

    func createInlineNote(collectionId: String, title: String? = nil, body: String) async throws -> Outline {
        var payload: [String: Any] = ["body": body]
        if let title { payload["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/collections/\(collectionId)/notes", method: "POST", body: data)
    }

    func compileCollection(
        id: String,
        title: String? = nil,
        includeFullContent: Bool = false
    ) async throws -> Draft {
        var payload: [String: Any] = ["include_full_content": includeFullContent]
        if let title { payload["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await request("/collections/\(id)/compile", method: "POST", body: data)
    }

    // MARK: - Chat (SSE)

    func streamChat(
        query: String,
        sourceTypes: [String]?,
        limit: Int = 8,
        history: [(role: String, content: String)] = []
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "/v1/chat", relativeTo: baseURL) else {
                        throw APIError.invalidURL
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if let key = apiKey, !key.isEmpty {
                        req.setValue(key, forHTTPHeaderField: "X-API-Key")
                    }
                    var payload: [String: Any] = ["query": query, "limit": limit]
                    if let sourceTypes { payload["source_types"] = sourceTypes }
                    if !history.isEmpty {
                        payload["history"] = history.map { ["role": $0.role, "content": $0.content] }
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.http(status: -1, body: "")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line + "\n"
                            if body.count > 500 { break }
                        }
                        throw APIError.http(status: http.statusCode, body: body)
                    }

                    var eventName: String?
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            eventName = nil
                            continue
                        }
                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            guard let name = eventName else { continue }
                            let payload = String(line.dropFirst("data:".count))
                                .trimmingCharacters(in: .whitespaces)
                            guard
                                let data = payload.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }
                            if let event = ChatStreamEvent.parse(name: name, json: json) {
                                continuation.yield(event)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Admin

    func reindex() async throws -> [String: Int] {
        let body = try JSONSerialization.data(withJSONObject: [String: Any]())
        guard let url = URL(string: "/v1/admin/reindex", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            return [:]
        }
        return json
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
