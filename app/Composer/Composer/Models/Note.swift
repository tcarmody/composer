import Foundation

struct Note: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let body: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NoteListResponse: Decodable {
    let notes: [Note]
    let total: Int
}
