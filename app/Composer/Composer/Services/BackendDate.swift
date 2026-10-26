import Foundation

private extension TimeZone {
    static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
}

/// Parsing for the timestamps the backend hands out.
///
/// They arrive in three shapes, and two of them carry no time zone:
///
///     2026-09-17 21:45:18          SQLite datetime('now') — space separator
///     2026-05-13T00:18:08.266950   Python isoformat, by way of DataPoints
///     2026-05-08T12:00:00+00:00    ISO 8601 with an offset, from article metadata
///
/// The zone-less two are UTC. SQLite's `datetime('now')` is UTC by definition,
/// and the DataPoints values are generated alongside it. Reading them in the
/// local zone — which a bare `DateFormatter` does by omission, and did here —
/// shifts every displayed time by the local UTC offset.
enum BackendDate {
    /// `nil` for empty input or a shape we don't recognize.
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Sub-second precision is never displayed, and the digit count varies
        // by producer — 3 from JavaScript, 6 from Python. Drop it rather than
        // trying to match every width.
        let normalized = trimmed.replacingOccurrences(
            of: #":(\d{2})\.\d+"#,
            with: ":$1",
            options: .regularExpression
        )

        if hasZone(normalized) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: normalized) { return date }
        }

        for format in zonelessFormats {
            if let date = formatter(format, in: .utc).date(from: normalized) { return date }
        }

        // A bare calendar date is a date, not an instant. Reading it as UTC
        // midnight renders it a day early anywhere west of Greenwich, so take
        // it in the local zone and let it display as written.
        return formatter(dateOnlyFormat, in: .current).date(from: normalized)
    }

    /// "Sep 14" — for list rows, where the year is noise.
    static func shortDate(_ raw: String?) -> String {
        guard let date = parse(raw) else { return fallback(raw) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Sep 14, 2026 at 4:18 PM" — for detail views and sort-order cues.
    static func dateTime(_ raw: String?) -> String {
        guard let date = parse(raw) else { return fallback(raw) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Internals

    /// Showing the raw value beats showing nothing when the shape is new —
    /// it's the only clue that a producer changed its format.
    private static func fallback(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static let zonelessFormats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
    ]

    private static let dateOnlyFormat = "yyyy-MM-dd"

    private static func hasZone(_ value: String) -> Bool {
        if value.hasSuffix("Z") { return true }
        return value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
    }

    private static func formatter(_ format: String, in zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        // Fixed-format parsing needs a fixed locale, or a user on a non-
        // Gregorian calendar fails to parse perfectly good input.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }
}
