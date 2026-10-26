import Foundation
import Testing

@testable import Composer

// The three shapes below are the ones actually present in data/composer.db.
// Assertions are on `parse`, which returns an absolute instant and so is
// independent of the machine's locale and zone — unlike `shortDate` and
// `dateTime`, which format through the ambient locale on purpose.

/// An instant built explicitly in UTC, so the expectation never depends on
/// where the test runs.
private func utc(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}

@Suite("BackendDate parsing")
struct BackendDateParsingTests {
    @Test("SQLite datetime('now') is read as UTC, not local")
    func sqliteTimestamp() throws {
        // The regression: no timeZone on the formatter meant this came back
        // shifted by the local UTC offset.
        let parsed = try #require(BackendDate.parse("2026-09-17 21:45:18"))
        #expect(parsed == utc(2026, 9, 17, 21, 45, 18))
    }

    @Test("Python isoformat with microseconds and no zone")
    func pythonMicroseconds() throws {
        // 33 rows in the library looked like this and matched no format at
        // all, so the raw string was rendered into the list.
        let parsed = try #require(BackendDate.parse("2026-05-13T00:18:08.266950"))
        #expect(parsed == utc(2026, 5, 13, 0, 18, 8))
    }

    @Test("ISO 8601 with an explicit offset")
    func isoWithOffset() throws {
        let parsed = try #require(BackendDate.parse("2026-05-08T12:00:00+00:00"))
        #expect(parsed == utc(2026, 5, 8, 12, 0, 0))
    }

    @Test("Zulu designator, with and without fractional seconds")
    func zuluForms() throws {
        let plain = try #require(BackendDate.parse("2026-05-08T12:00:00Z"))
        let fractional = try #require(BackendDate.parse("2026-05-08T12:00:00.266Z"))
        #expect(plain == utc(2026, 5, 8, 12, 0, 0))
        #expect(fractional == utc(2026, 5, 8, 12, 0, 0))
    }

    @Test("A non-zero offset is honored rather than ignored")
    func nonZeroOffset() throws {
        // 09:00 at +02:00 is 07:00 UTC. Dropping the offset would land on 09:00.
        let parsed = try #require(BackendDate.parse("2026-05-08T09:00:00+02:00"))
        #expect(parsed == utc(2026, 5, 8, 7, 0, 0))
    }

    @Test("The same instant in three shapes parses to one value")
    func shapesAgree() throws {
        let sqlite = try #require(BackendDate.parse("2026-05-08 12:00:00"))
        let offset = try #require(BackendDate.parse("2026-05-08T12:00:00+00:00"))
        let python = try #require(BackendDate.parse("2026-05-08T12:00:00.000000"))
        #expect(sqlite == offset)
        #expect(offset == python)
    }

    @Test("A bare calendar date keeps its day in the local zone")
    func dateOnlyKeepsItsDay() throws {
        // Read as UTC midnight this renders a day early anywhere west of
        // Greenwich, which is what the first cut of the parser did.
        let parsed = try #require(BackendDate.parse("2026-09-14"))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: parsed)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 14)
    }

    @Test("Surrounding whitespace is tolerated")
    func trimsWhitespace() throws {
        let parsed = try #require(BackendDate.parse("  2026-09-17 21:45:18\n"))
        #expect(parsed == utc(2026, 9, 17, 21, 45, 18))
    }

    @Test("Nothing to parse", arguments: [nil, "", "   "] as [String?])
    func emptyInput(raw: String?) {
        #expect(BackendDate.parse(raw) == nil)
        #expect(BackendDate.shortDate(raw) == "")
        #expect(BackendDate.dateTime(raw) == "")
    }

    @Test("An unrecognized shape falls back to the raw value")
    func unknownShapeFallsBack() {
        // Better than a blank cell: it's the only visible clue that some
        // producer changed its format.
        #expect(BackendDate.parse("last Tuesday") == nil)
        #expect(BackendDate.shortDate("last Tuesday") == "last Tuesday")
        #expect(BackendDate.dateTime("  last Tuesday  ") == "last Tuesday")
    }

    @Test("Formatted output is not the raw string for known shapes")
    func formattingProducesRealDates() {
        // Locale-independent assertion: whatever the machine's format, it is
        // not the input echoed back.
        for raw in [
            "2026-09-17 21:45:18",
            "2026-05-13T00:18:08.266950",
            "2026-05-08T12:00:00+00:00",
        ] {
            #expect(BackendDate.shortDate(raw) != raw)
            #expect(BackendDate.dateTime(raw) != raw)
        }
    }
}
