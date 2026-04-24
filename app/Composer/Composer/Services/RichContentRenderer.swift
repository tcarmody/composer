import AppKit
import Foundation

enum RichContentRenderer {
    static func render(_ content: String) -> NSAttributedString {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString(string: "") }
        if looksLikeHTML(trimmed), let html = renderHTML(trimmed) {
            return html
        }
        return MarkdownConverter.attributedString(from: content)
    }

    private static let htmlTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<[a-zA-Z][a-zA-Z0-9]*(\\s[^>]*)?/?>|</[a-zA-Z][a-zA-Z0-9]*\\s*>"
    )

    private static func looksLikeHTML(_ s: String) -> Bool {
        guard let re = htmlTagRegex else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return re.firstMatch(in: s, options: [], range: range) != nil
    }

    private static func renderHTML(_ raw: String) -> NSAttributedString? {
        let sanitized = stripScriptsAndHandlers(raw)
        let bodySize = Int(Typography.bodySize)
        let wrapped = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; font-size: \(bodySize)px; line-height: 1.45; margin: 0; padding: 0; }
        p { margin: 0 0 0.6em 0; }
        blockquote { border-left: 3px solid rgba(127,127,127,0.35); margin: 0.5em 0; padding: 0.25em 0 0.25em 0.75em; }
        ul, ol { margin: 0.4em 0; padding-left: 1.5em; }
        li { margin: 0.1em 0; }
        h1, h2, h3, h4, h5, h6 { margin: 0.6em 0 0.3em 0; font-weight: 600; }
        code { font-family: ui-monospace, Menlo, monospace; font-size: 0.95em; background: rgba(127,127,127,0.15); padding: 0 3px; border-radius: 3px; }
        pre { font-family: ui-monospace, Menlo, monospace; background: rgba(127,127,127,0.12); padding: 8px; border-radius: 4px; overflow-x: auto; }
        img { max-width: 100%; height: auto; }
        a { color: #0a7bff; text-decoration: none; }
        </style></head><body>\(sanitized)</body></html>
        """
        guard let data = wrapped.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    private static func stripScriptsAndHandlers(_ html: String) -> String {
        var s = html
        let patterns = [
            "<script\\b[^<]*(?:(?!</script>)<[^<]*)*</script>",
            "<style\\b[^<]*(?:(?!</style>)<[^<]*)*</style>",
            "\\son[a-zA-Z]+\\s*=\\s*\"[^\"]*\"",
            "\\son[a-zA-Z]+\\s*=\\s*'[^']*'",
            "\\son[a-zA-Z]+\\s*=\\s*[^\\s>]+",
            "javascript:",
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            }
        }
        return s
    }
}
