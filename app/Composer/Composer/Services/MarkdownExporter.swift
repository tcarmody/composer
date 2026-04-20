import Foundation

enum MarkdownExporter {
    static func html(from markdown: String, title: String?) -> String {
        let body = htmlBody(from: markdown)
        let escapedTitle = escapeHTML(title?.isEmpty == false ? title! : "Untitled")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    static func htmlBody(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("### ") {
                out.append("<h3>\(renderInline(String(line.dropFirst(4))))</h3>")
                i += 1
            } else if line.hasPrefix("## ") {
                out.append("<h2>\(renderInline(String(line.dropFirst(3))))</h2>")
                i += 1
            } else if line.hasPrefix("# ") {
                out.append("<h1>\(renderInline(String(line.dropFirst(2))))</h1>")
                i += 1
            } else if line.hasPrefix("> ") {
                var buf: [String] = []
                while i < lines.count, lines[i].hasPrefix("> ") {
                    buf.append(renderInline(String(lines[i].dropFirst(2))))
                    i += 1
                }
                out.append("<blockquote>\(buf.joined(separator: "<br>"))</blockquote>")
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var buf: [String] = []
                while i < lines.count,
                      lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ") {
                    let content = String(lines[i].dropFirst(2))
                    buf.append("<li>\(renderInline(content))</li>")
                    i += 1
                }
                out.append("<ul>\n" + buf.joined(separator: "\n") + "\n</ul>")
            } else if matchesNumberedPrefix(line) {
                var buf: [String] = []
                while i < lines.count, matchesNumberedPrefix(lines[i]) {
                    let content = stripNumberedPrefix(lines[i])
                    buf.append("<li>\(renderInline(content))</li>")
                    i += 1
                }
                out.append("<ol>\n" + buf.joined(separator: "\n") + "\n</ol>")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
            } else if line.trimmingCharacters(in: .whitespaces) == "---" {
                out.append("<hr>")
                i += 1
            } else {
                out.append("<p>\(renderInline(line))</p>")
                i += 1
            }
        }
        return out.joined(separator: "\n")
    }

    private static func matchesNumberedPrefix(_ line: String) -> Bool {
        var seen = false
        for ch in line {
            if ch.isNumber { seen = true; continue }
            if ch == "." && seen { return true }
            return false
        }
        return false
    }

    private static func stripNumberedPrefix(_ line: String) -> String {
        guard let dot = line.firstIndex(of: ".") else { return line }
        let after = line.index(after: dot)
        var s = String(line[after...])
        if s.first == " " { s.removeFirst() }
        return s
    }

    private static func renderInline(_ source: String) -> String {
        var result = ""
        var i = source.startIndex
        while i < source.endIndex {
            let c = source[i]
            if c == "`" {
                if let end = nextDelimiter(source, after: i, delimiter: "`") {
                    let inner = String(source[source.index(after: i)..<end])
                    result += "<code>\(escapeHTML(inner))</code>"
                    i = source.index(after: end)
                    continue
                }
            }
            if c == "[" {
                if let close = source[i...].firstIndex(of: "]"),
                   source.index(after: close) < source.endIndex,
                   source[source.index(after: close)] == "(",
                   let urlEnd = source[source.index(after: close)...].firstIndex(of: ")") {
                    let text = String(source[source.index(after: i)..<close])
                    let urlStart = source.index(close, offsetBy: 2)
                    let url = String(source[urlStart..<urlEnd])
                    result += "<a href=\"\(escapeHTML(url))\">\(renderInline(text))</a>"
                    i = source.index(after: urlEnd)
                    continue
                }
            }
            if c == "*" || c == "_" {
                let isDouble = source.index(after: i) < source.endIndex
                    && source[source.index(after: i)] == c
                if isDouble {
                    let scanFrom = source.index(i, offsetBy: 2)
                    if let end = matchDoubleDelimiter(source, from: scanFrom, delimiter: c) {
                        let inner = String(source[scanFrom..<end])
                        result += "<strong>\(renderInline(inner))</strong>"
                        i = source.index(end, offsetBy: 2)
                        continue
                    }
                } else if let end = nextDelimiter(source, after: i, delimiter: c) {
                    let inner = String(source[source.index(after: i)..<end])
                    result += "<em>\(renderInline(inner))</em>"
                    i = source.index(after: end)
                    continue
                }
            }
            result += escapeChar(c)
            i = source.index(after: i)
        }
        return result
    }

    private static func nextDelimiter(
        _ s: String, after start: String.Index, delimiter: Character
    ) -> String.Index? {
        var i = s.index(after: start)
        while i < s.endIndex {
            if s[i] == delimiter { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private static func matchDoubleDelimiter(
        _ s: String, from start: String.Index, delimiter: Character
    ) -> String.Index? {
        var i = start
        while i < s.endIndex {
            if s[i] == delimiter,
               s.index(after: i) < s.endIndex,
               s[s.index(after: i)] == delimiter {
                return i
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func escapeChar(_ c: Character) -> String {
        switch c {
        case "&": return "&amp;"
        case "<": return "&lt;"
        case ">": return "&gt;"
        case "\"": return "&quot;"
        default: return String(c)
        }
    }

    private static func escapeHTML(_ s: String) -> String {
        var out = ""
        for c in s { out += escapeChar(c) }
        return out
    }
}
