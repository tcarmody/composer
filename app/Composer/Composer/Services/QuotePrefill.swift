import Foundation

enum QuoteKind {
    case note
    case draft
}

struct QuoteSource {
    let title: String?
    let author: String?
    let url: String?
}

enum QuotePrefill {
    static func build(selection: String, source: QuoteSource) -> String {
        let quote = selection
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")

        let rawTitle = source.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = rawTitle.isEmpty ? "Untitled" : rawTitle
        let titleLink: String
        if let url = source.url, !url.isEmpty {
            titleLink = "[\(title)](\(url))"
        } else {
            titleLink = title
        }

        let attribution: String
        if let author = source.author, !author.isEmpty {
            attribution = "— \(author), \(titleLink)"
        } else {
            attribution = "— \(titleLink)"
        }

        return "\(quote)\n\n\(attribution)\n\n"
    }
}

extension Item {
    var quoteSource: QuoteSource {
        QuoteSource(title: title, author: author, url: url)
    }
}
