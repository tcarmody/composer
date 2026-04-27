import AppKit
import Foundation

enum SmartQuotes {
    static let leftDouble: Character = "\u{201C}"
    static let rightDouble: Character = "\u{201D}"
    static let leftSingle: Character = "\u{2018}"
    static let rightSingle: Character = "\u{2019}"

    /// Converts straight quotes (`"` and `'`) to typographic curly quotes,
    /// skipping markdown fenced code blocks and inline code spans so code stays
    /// byte-for-byte unchanged.
    static func convert(_ input: String) -> String {
        var output = ""
        output.reserveCapacity(input.count)

        var inFence = false
        var fenceChar: Character? = nil
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)

        for (idx, slice) in lines.enumerated() {
            let line = String(slice)
            let trimmed = line.drop(while: { $0 == " " })
            let isFenceLine: Bool = {
                guard let first = trimmed.first, first == "`" || first == "~" else { return false }
                return trimmed.hasPrefix(String(repeating: first, count: 3))
            }()

            if isFenceLine, let first = trimmed.first {
                if !inFence {
                    inFence = true
                    fenceChar = first
                    output.append(line)
                } else if first == fenceChar {
                    inFence = false
                    fenceChar = nil
                    output.append(line)
                } else {
                    output.append(line)
                }
            } else if inFence {
                output.append(line)
            } else {
                output.append(convertLine(line))
            }

            if idx < lines.count - 1 {
                output.append("\n")
            }
        }
        return output
    }

    /// Replaces straight quotes inside `storage`, preserving attributes by
    /// swapping changed characters one-at-a-time. Returns the number of swaps.
    @discardableResult
    @MainActor
    static func convertInPlace(_ storage: NSTextStorage, range: NSRange? = nil) -> Int {
        let target = range ?? NSRange(location: 0, length: storage.length)
        guard target.length > 0 else { return 0 }
        let originalNS = (storage.string as NSString).substring(with: target) as NSString
        let convertedNS = convert(originalNS as String) as NSString
        guard originalNS.length == convertedNS.length else {
            // Fallback: shouldn't happen since each substitution is single-BMP-unit.
            storage.beginEditing()
            storage.replaceCharacters(in: target, with: convertedNS as String)
            storage.endEditing()
            return target.length
        }
        var changes = 0
        storage.beginEditing()
        for i in 0..<originalNS.length {
            let oc = originalNS.character(at: i)
            let nc = convertedNS.character(at: i)
            if oc != nc {
                let absolute = NSRange(location: target.location + i, length: 1)
                let replacement = String(utf16CodeUnits: [nc], count: 1)
                storage.replaceCharacters(in: absolute, with: replacement)
                changes += 1
            }
        }
        storage.endEditing()
        return changes
    }

    private static func convertLine(_ line: String) -> String {
        let chars = Array(line)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "`" {
                let runStart = i
                var runLen = 1
                while i + runLen < chars.count && chars[i + runLen] == "`" {
                    runLen += 1
                }
                if let closeStart = findMatchingBacktickRun(chars, start: runStart + runLen, length: runLen) {
                    let end = closeStart + runLen
                    result.append(String(chars[runStart..<end]))
                    i = end
                } else {
                    result.append(String(chars[runStart..<(runStart + runLen)]))
                    i = runStart + runLen
                }
                continue
            }

            let prev = result.last
            if c == "\"" {
                let opening = isOpeningContext(prev: prev)
                result.append(opening ? leftDouble : rightDouble)
                i += 1
                continue
            }
            if c == "'" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                result.append(curlySingle(prev: prev, next: next))
                i += 1
                continue
            }
            result.append(c)
            i += 1
        }
        return result
    }

    private static func findMatchingBacktickRun(_ chars: [Character], start: Int, length: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                var endLen = 1
                while j + endLen < chars.count && chars[j + endLen] == "`" {
                    endLen += 1
                }
                if endLen == length {
                    return j
                }
                j += endLen
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func isOpeningContext(prev: Character?) -> Bool {
        guard let p = prev else { return true }
        if p.isWhitespace { return true }
        return "([{<\u{2014}\u{2013}-".contains(p)
    }

    private static func curlySingle(prev: Character?, next: Character?) -> Character {
        let prevIsAlnum = prev.map { $0.isLetter || $0.isNumber } ?? false
        let nextIsAlnum = next.map { $0.isLetter || $0.isNumber } ?? false
        if prevIsAlnum { return rightSingle }
        if isOpeningContext(prev: prev) && nextIsAlnum { return leftSingle }
        return rightSingle
    }
}
