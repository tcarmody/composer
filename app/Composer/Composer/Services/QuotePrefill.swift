import Foundation

enum QuoteKind {
    case note
    case draft
    case appendToDraft
}

struct QuoteSource {
    let title: String?
    let author: String?
    let url: String?
    let publishedAt: String?
    let itemId: String?
}

enum QuotePrefill {
    static func build(selection: String, source: QuoteSource, smartQuotes: Bool = false) -> String {
        let quoteText = smartQuotes ? SmartQuotes.convert(selection) : selection
        let quote = quoteText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return "\(quote)\n\n\(attribution(for: source, smartQuotes: smartQuotes))\n\n"
    }

    static func attribution(for source: QuoteSource, smartQuotes: Bool = false) -> String {
        let rawTitle = source.title?.trimmingCharacters(in: .whitespaces) ?? ""
        var title = rawTitle.isEmpty ? "Untitled" : rawTitle
        if smartQuotes { title = SmartQuotes.convert(title) }
        let titleLink: String
        if let url = source.url, !url.isEmpty {
            titleLink = "[\(title)](\(url))"
        } else {
            titleLink = title
        }
        var parts: [String] = []
        if let rawAuthor = source.author, !rawAuthor.isEmpty {
            parts.append(smartQuotes ? SmartQuotes.convert(rawAuthor) : rawAuthor)
        }
        parts.append(titleLink)
        if let date = formatDate(source.publishedAt) {
            parts.append("(\(date))")
        }
        return "— " + parts.joined(separator: ", ")
    }

    private static func formatDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            return d.formatted(.dateTime.month(.abbreviated).day().year())
        }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        if let d = fallback.date(from: String(iso.prefix(10))) {
            return d.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return nil
    }
}

extension Item {
    var quoteSource: QuoteSource {
        QuoteSource(title: title, author: author, url: url, publishedAt: publishedAt, itemId: id)
    }
}
