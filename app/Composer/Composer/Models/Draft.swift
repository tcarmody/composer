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
    case audio

    var label: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .expand: return "Expand"
        case .summarize: return "Summarize"
        case .tighten: return "Tighten"
        case .audio: return "Audio"
        }
    }

    var description: String {
        switch self {
        case .rewrite: return "Rewrite for clarity and directness"
        case .expand: return "Expand with more detail and examples"
        case .summarize: return "Summarize in one tight paragraph"
        case .tighten: return "Cut hedging and filler"
        case .audio: return "Rewrite as a script to be read aloud"
        }
    }
}

struct DraftAssistResponse: Decodable {
    let suggestion: String
}

struct DraftSource: Decodable, Identifiable, Hashable {
    let id: Int
    let draftId: String
    let itemId: String
    let excerpt: String?
    let addedAt: String
    let itemTitle: String?
    let itemAuthor: String?
    let itemUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, excerpt
        case draftId = "draft_id"
        case itemId = "item_id"
        case addedAt = "added_at"
        case itemTitle = "item_title"
        case itemAuthor = "item_author"
        case itemUrl = "item_url"
    }
}

struct DraftSourceListResponse: Decodable {
    let sources: [DraftSource]
}
