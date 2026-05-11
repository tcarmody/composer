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
        let url = source.url?.trimmingCharacters(in: .whitespaces) ?? ""
        let outlet = outletName(forURL: url) ?? fallbackLabel(for: source, smartQuotes: smartQuotes)
        if url.isEmpty {
            return "— \(outlet)"
        }
        return "— [\(outlet)](\(url))"
    }

    /// Best-effort outlet/publisher label derived from the URL host.
    /// Strips common subdomain prefixes (`www.`, `m.`, `amp.`).
    static func outletName(forURL urlString: String) -> String? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host, !host.isEmpty else { return nil }
        var cleaned = host
        for prefix in ["www.", "m.", "amp."] {
            if cleaned.hasPrefix(prefix) {
                cleaned.removeFirst(prefix.count)
                break
            }
        }
        return cleaned
    }

    private static func fallbackLabel(for source: QuoteSource, smartQuotes: Bool) -> String {
        let title = (source.title ?? "").trimmingCharacters(in: .whitespaces)
        if title.isEmpty { return "Source" }
        return smartQuotes ? SmartQuotes.convert(title) : title
    }
}

extension Item {
    var quoteSource: QuoteSource {
        QuoteSource(title: title, author: author, url: url, publishedAt: publishedAt, itemId: id)
    }
}
