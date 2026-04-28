import Foundation

enum FactCheckVerdict: String {
    case supported
    case contradicted
    case unverified
    case needsContext = "needs_context"

    var label: String {
        switch self {
        case .supported: return "Supported"
        case .contradicted: return "Contradicted"
        case .unverified: return "Unverified"
        case .needsContext: return "Needs context"
        }
    }

    var symbol: String {
        switch self {
        case .supported: return "checkmark.circle.fill"
        case .contradicted: return "xmark.octagon.fill"
        case .unverified: return "questionmark.circle"
        case .needsContext: return "exclamationmark.triangle.fill"
        }
    }
}

struct FactCheckSource: Identifiable, Hashable {
    let title: String
    let url: String
    let snippet: String?

    var id: String { url }

    init?(json: [String: Any]) {
        guard let url = (json["url"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) else {
            return nil
        }
        self.url = url
        self.title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url
        self.snippet = (json["snippet"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct FactCheckExtractedClaim: Identifiable, Hashable {
    let id: String
    let claim: String
    let kind: String?
    let offset: Int?
    let length: Int?

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let claim = json["claim"] as? String,
              !claim.isEmpty else { return nil }
        self.id = id
        self.claim = claim
        self.kind = json["kind"] as? String
        self.offset = json["offset"] as? Int
        self.length = json["length"] as? Int
    }
}

enum FactCheckStreamEvent {
    case extracted([FactCheckExtractedClaim])
    case verdict(
        claimId: String,
        verdict: FactCheckVerdict,
        explanation: String,
        suggestedCorrection: String?,
        sources: [FactCheckSource]
    )
    case done(modelUsed: String)
    case error(message: String, claimId: String?)

    static func parse(name: String, json: [String: Any]) -> FactCheckStreamEvent? {
        switch name {
        case "extracted":
            let arr = (json["claims"] as? [[String: Any]]) ?? []
            return .extracted(arr.compactMap(FactCheckExtractedClaim.init(json:)))
        case "verdict":
            guard let claimId = json["claim_id"] as? String,
                  let verdictRaw = json["verdict"] as? String,
                  let verdict = FactCheckVerdict(rawValue: verdictRaw) else {
                return nil
            }
            let explanation = (json["explanation"] as? String) ?? ""
            let correction = (json["suggested_correction"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
            let sources = ((json["sources"] as? [[String: Any]]) ?? [])
                .compactMap(FactCheckSource.init(json:))
            return .verdict(
                claimId: claimId,
                verdict: verdict,
                explanation: explanation,
                suggestedCorrection: correction,
                sources: sources
            )
        case "done":
            return .done(modelUsed: (json["model_used"] as? String) ?? "")
        case "error":
            return .error(
                message: (json["message"] as? String) ?? "Unknown error",
                claimId: json["claim_id"] as? String
            )
        default:
            return nil
        }
    }
}

struct FactCheckClaimState: Identifiable {
    enum Status {
        case pending
        case verified
        case failed(String)
    }

    let id: String
    let claim: String
    let kind: String?
    var status: Status
    var verdict: FactCheckVerdict?
    var explanation: String = ""
    var suggestedCorrection: String?
    var sources: [FactCheckSource] = []
}
