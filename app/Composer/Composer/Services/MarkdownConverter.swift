import AppKit
import Foundation

enum ParagraphKind: String {
    case body
    case heading1
    case heading2
    case heading3
    case bullet
    case numbered
    case blockquote
    case codeBlock
}

extension NSAttributedString.Key {
    static let paragraphKind = NSAttributedString.Key("composer.paragraphKind")
    static let inlineCode = NSAttributedString.Key("composer.inlineCode")
}

enum Typography {
    static let bodySize: CGFloat = 14
    static let heading1Size: CGFloat = 26
    static let heading2Size: CGFloat = 21
    static let heading3Size: CGFloat = 17

    static func font(for kind: ParagraphKind) -> NSFont {
        switch kind {
        case .body, .bullet, .numbered, .blockquote:
            return .systemFont(ofSize: bodySize)
        case .heading1:
            return .systemFont(ofSize: heading1Size, weight: .semibold)
        case .heading2:
            return .systemFont(ofSize: heading2Size, weight: .semibold)
        case .heading3:
            return .systemFont(ofSize: heading3Size, weight: .semibold)
        case .codeBlock:
            return .monospacedSystemFont(ofSize: bodySize, weight: .regular)
        }
    }

    static func paragraphStyle(for kind: ParagraphKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch kind {
        case .heading1, .heading2, .heading3:
            style.paragraphSpacing = 6
            style.paragraphSpacingBefore = 4
        case .bullet, .numbered:
            style.headIndent = 18
            style.firstLineHeadIndent = 0
        case .blockquote:
            style.headIndent = 16
            style.firstLineHeadIndent = 16
        default:
            break
        }
        return style
    }
}

enum MarkdownConverter {
    // MARK: - Markdown → NSAttributedString

    static func attributedString(from markdown: String) -> NSAttributedString {
        let lines = markdown.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        for (idx, line) in lines.enumerated() {
            let paragraph = parseLine(line)
            out.append(paragraph)
            if idx < lines.count - 1 {
                out.append(NSAttributedString(
                    string: "\n",
                    attributes: [.paragraphKind: ParagraphKind.body.rawValue]
                ))
            }
        }
        return out
    }

    private static func parseLine(_ line: String) -> NSAttributedString {
        let (kind, stripped) = detectKind(line)
        let inline = parseInline(stripped)
        let mutable = NSMutableAttributedString(attributedString: inline)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let baseFont = Typography.font(for: kind)
        let paraStyle = Typography.paragraphStyle(for: kind)

        mutable.addAttributes([
            .paragraphKind: kind.rawValue,
            .paragraphStyle: paraStyle
        ], range: fullRange)

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let existing = value as? NSFont
            let traits = existing.map {
                NSFontManager.shared.traits(of: $0)
            } ?? NSFontTraitMask()
            var font = baseFont
            if traits.contains(.boldFontMask) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            mutable.addAttribute(.font, value: font, range: range)
        }

        if mutable.length == 0 {
            mutable.append(NSAttributedString(
                string: "",
                attributes: [
                    .paragraphKind: kind.rawValue,
                    .paragraphStyle: paraStyle,
                    .font: baseFont
                ]
            ))
        }
        return mutable
    }

    private static func detectKind(_ line: String) -> (ParagraphKind, String) {
        if line.hasPrefix("### ") { return (.heading3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ") { return (.heading2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ") { return (.heading1, String(line.dropFirst(2))) }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return (.bullet, String(line.dropFirst(2))) }
        if line.hasPrefix("> ") { return (.blockquote, String(line.dropFirst(2))) }
        if let match = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
            return (.numbered, String(line[match.upperBound...]))
        }
        return (.body, line)
    }

    private static func parseInline(_ text: String) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: "") }
        var attributed = AttributedString(text)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: text, options: options) {
            attributed = parsed
        }
        let ns = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        translateCodeRuns(in: ns)
        return ns
    }

    private static func translateCodeRuns(in ns: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: ns.length)
        ns.enumerateAttribute(.init("NSInlinePresentationIntent"), in: fullRange, options: []) { value, range, _ in
            guard let raw = value as? UInt64 else { return }
            if raw & 0b100 != 0 {
                ns.addAttribute(.inlineCode, value: true, range: range)
                ns.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: Typography.bodySize, weight: .regular),
                    range: range
                )
            }
        }
    }

    // MARK: - NSAttributedString → Markdown

    static func markdown(from attributed: NSAttributedString) -> String {
        let nsString = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var lines: [String] = []
        var paraStart = 0

        while paraStart < nsString.length {
            let nlRange = nsString.range(of: "\n", range: NSRange(location: paraStart, length: nsString.length - paraStart))
            let paraRange: NSRange
            if nlRange.location == NSNotFound {
                paraRange = NSRange(location: paraStart, length: nsString.length - paraStart)
                paraStart = nsString.length
            } else {
                paraRange = NSRange(location: paraStart, length: nlRange.location - paraStart)
                paraStart = nlRange.location + 1
            }
            lines.append(serializeParagraph(attributed, range: paraRange))
        }

        if fullRange.length > 0, nsString.hasSuffix("\n") {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func serializeParagraph(_ attributed: NSAttributedString, range: NSRange) -> String {
        let kind = paragraphKind(at: range.location, in: attributed)
        let inline = serializeInline(attributed, range: range)

        switch kind {
        case .body: return inline
        case .heading1: return "# \(inline)"
        case .heading2: return "## \(inline)"
        case .heading3: return "### \(inline)"
        case .bullet: return "- \(inline)"
        case .numbered: return "1. \(inline)"
        case .blockquote: return "> \(inline)"
        case .codeBlock: return "    \(inline)"
        }
    }

    private static func paragraphKind(at location: Int, in attributed: NSAttributedString) -> ParagraphKind {
        guard attributed.length > 0 else { return .body }
        let probe = min(location, attributed.length - 1)
        if let raw = attributed.attribute(.paragraphKind, at: probe, effectiveRange: nil) as? String,
           let kind = ParagraphKind(rawValue: raw) {
            return kind
        }
        return .body
    }

    private static func serializeInline(_ attributed: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var result = ""
        attributed.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            let raw = (attributed.string as NSString).substring(with: subrange)
            var piece = escape(raw)
            if attrs[.inlineCode] as? Bool == true {
                piece = "`\(raw)`"
            } else {
                var bold = false, italic = false
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    bold = traits.contains(.boldFontMask)
                    italic = traits.contains(.italicFontMask)
                }
                if bold { piece = "**\(piece)**" }
                if italic { piece = "*\(piece)*" }
            }
            if let link = attrs[.link] {
                let urlString: String
                if let url = link as? URL { urlString = url.absoluteString }
                else if let str = link as? String { urlString = str }
                else { urlString = "" }
                if !urlString.isEmpty {
                    piece = "[\(piece)](\(urlString))"
                }
            }
            result += piece
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "\\", "`", "*", "_", "[", "]":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }
}
