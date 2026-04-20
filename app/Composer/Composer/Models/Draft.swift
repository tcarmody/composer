import Foundation

enum DraftStatus: String, Codable, Hashable, CaseIterable {
    case wip
    case final

    var label: String {
        switch self {
        case .wip: return "Draft"
        case .final: return "Final"
        }
    }
}

struct Draft: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let body: String
    let status: DraftStatus
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DraftListResponse: Decodable {
    let drafts: [Draft]
    let total: Int
}
