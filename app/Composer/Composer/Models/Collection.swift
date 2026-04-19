import Foundation

enum MemberType: String, Codable {
    case item
    case note
    case draft
}

struct Collection: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let createdAt: String
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdAt = "created_at"
        case memberCount = "member_count"
    }
}

struct OutlineItemPayload: Decodable, Hashable {
    let id: String
    let title: String?
    let author: String?
    let summary: String?
    let publishedAt: String?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, author, summary, archived
        case publishedAt = "published_at"
    }
}

struct OutlineNotePayload: Decodable, Hashable {
    let id: String
    let title: String?
    let body: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case updatedAt = "updated_at"
    }
}

struct OutlineNode: Decodable, Identifiable, Hashable {
    let memberType: MemberType
    let memberId: String
    let position: Int
    let item: OutlineItemPayload?
    let note: OutlineNotePayload?

    enum CodingKeys: String, CodingKey {
        case memberType = "member_type"
        case memberId = "member_id"
        case position, item, note
    }

    var id: String { "\(memberType.rawValue):\(memberId)" }
}

struct Outline: Decodable, Hashable {
    let collection: Collection
    let members: [OutlineNode]
}
