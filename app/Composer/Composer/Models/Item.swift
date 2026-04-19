import Foundation

struct RelatedLink: Decodable, Hashable {
    let url: String
    let title: String?
    let score: Double?
}

struct ItemSummary: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let url: String?
    let title: String
    let author: String?
    let publishedAt: String?
    let promotedAt: String
    let summary: String?
    let keyPoints: [String]
    let keywords: [String]
    let archivedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source, url, title, author, summary, keywords
        case publishedAt = "published_at"
        case promotedAt = "promoted_at"
        case keyPoints = "key_points"
        case archivedAt = "archived_at"
    }

    var isArchived: Bool { archivedAt != nil }
}

struct Item: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let sourceRef: String?
    let url: String?
    let title: String
    let author: String?
    let publishedAt: String?
    let promotedAt: String
    let summary: String?
    let keyPoints: [String]
    let keywords: [String]
    let archivedAt: String?
    let content: String?
    let relatedLinks: [RelatedLink]

    enum CodingKeys: String, CodingKey {
        case id, source, url, title, author, summary, keywords, content
        case sourceRef = "source_ref"
        case publishedAt = "published_at"
        case promotedAt = "promoted_at"
        case keyPoints = "key_points"
        case archivedAt = "archived_at"
        case relatedLinks = "related_links"
    }

    var isArchived: Bool { archivedAt != nil }
}

struct ItemListResponse: Decodable {
    let items: [ItemSummary]
    let total: Int
    let limit: Int
    let offset: Int
}
