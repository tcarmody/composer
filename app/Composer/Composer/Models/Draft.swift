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

enum DraftAssistAction: String, Codable, CaseIterable {
    case rewrite
    case expand
    case summarize
    case tighten

    var label: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .expand: return "Expand"
        case .summarize: return "Summarize"
        case .tighten: return "Tighten"
        }
    }

    var description: String {
        switch self {
        case .rewrite: return "Rewrite for clarity and directness"
        case .expand: return "Expand with more detail and examples"
        case .summarize: return "Summarize in one tight paragraph"
        case .tighten: return "Cut hedging and filler"
        }
    }
}

struct DraftAssistResponse: Decodable {
    let suggestion: String
}
