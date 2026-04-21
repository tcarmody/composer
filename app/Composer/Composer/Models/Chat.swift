import Foundation

struct Citation: Identifiable, Equatable {
    let index: Int
    let chunkId: String
    let sourceType: String
    let sourceId: String
    let sourceTitle: String?
    let sourceURL: String?
    let chunkIndex: Int
    let snippet: String

    var id: String { chunkId }

    init?(json: [String: Any]) {
        guard
            let index = json["index"] as? Int,
            let chunkId = json["chunk_id"] as? String,
            let sourceType = json["source_type"] as? String,
            let sourceId = json["source_id"] as? String,
            let snippet = json["snippet"] as? String
        else { return nil }
        self.index = index
        self.chunkId = chunkId
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sourceTitle = json["source_title"] as? String
        self.sourceURL = json["source_url"] as? String
        self.chunkIndex = (json["chunk_index"] as? Int) ?? 0
        self.snippet = snippet
    }
}

enum ChatStreamEvent {
    case citations([Citation], vectorSearchUsed: Bool)
    case delta(String)
    case done(stopReason: String?)
    case error(String)

    static func parse(name: String, json: [String: Any]) -> ChatStreamEvent? {
        switch name {
        case "citations":
            let arr = (json["citations"] as? [[String: Any]]) ?? []
            let vectorUsed = (json["vector_search_used"] as? Bool) ?? false
            return .citations(arr.compactMap(Citation.init(json:)), vectorSearchUsed: vectorUsed)
        case "delta":
            let text = (json["text"] as? String) ?? ""
            return .delta(text)
        case "done":
            return .done(stopReason: json["stop_reason"] as? String)
        case "error":
            return .error((json["message"] as? String) ?? "Unknown error")
        default:
            return nil
        }
    }
}

enum SourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case items = "Library"
    case notes = "Notes"
    case drafts = "Drafts"

    var id: String { rawValue }

    var sourceTypes: [String]? {
        switch self {
        case .all: return nil
        case .items: return ["item"]
        case .notes: return ["note"]
        case .drafts: return ["draft"]
        }
    }
}
