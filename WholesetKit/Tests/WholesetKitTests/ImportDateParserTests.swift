// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: date parsing")
struct ImportDateParserTests {
    private let zone = ImportFixture.berlin
    private var parser: ImportDateParser { ImportDateParser(timeZone: zone) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        ImportFixture.date(year, month, day, hour, minute, second, zone: zone)
    }

    @Test("Hevy's localised dates, read as wall-clock time", arguments: [
        ("15 Sep 2025, 07:48", 2025, 9, 15, 7, 48),
        ("13 Feb 2026, 9:56", 2026, 2, 13, 9, 56),
        ("Apr 9, 2024, 3:44 PM", 2024, 4, 9, 15, 44),
        ("18 ago 2026, 12:27", 2026, 8, 18, 12, 27),
        ("20.01.2025, 12:00", 2025, 1, 20, 12, 0),
        ("20 janv. 2025, 12:00", 2025, 1, 20, 12, 0),
        ("1 sept. 2026, 12:00", 2026, 9, 1, 12, 0),
        ("2025/01/20 12:00", 2025, 1, 20, 12, 0),
        // Spanish, Brazilian Portuguese and Dutch month names.
        ("20 ene 2025, 12:00", 2025, 1, 20, 12, 0),
        ("1 sept 2026, 17:05", 2026, 9, 1, 17, 5),
        ("20 de jan. de 2025, 12:00", 2025, 1, 20, 12, 0),
        ("3 de out. de 2026, 08:15", 2026, 10, 3, 8, 15),
        ("20 jan 2025, 12:00", 2025, 1, 20, 12, 0),
        ("14 mrt 2026, 06:30", 2026, 3, 14, 6, 30),
        ("9 mei 2026, 19:45", 2026, 5, 9, 19, 45),
        // German with its own abbreviations, Italian, Japanese and Korean shapes.
        ("2. März 2026, 18:00", 2026, 3, 2, 18, 0),
        ("8 lug 2026, 18:39", 2026, 7, 8, 18, 39),
        ("2025年1月20日 12:00", 2025, 1, 20, 12, 0),
        ("2026년 9월 1일 오후 5:05", 2026, 9, 1, 17, 5),
        // Strong, FitNotes and StrongLifts.
        ("2026-03-02 17:45:00", 2026, 3, 2, 17, 45),
        ("2022-03-18", 2022, 3, 18, 0, 0),
        ("2026/02/03 11:40 PM", 2026, 2, 3, 23, 40),
        // 12 AM is midnight, 12 PM is noon; "p. m." with dots and spaces.
        ("Oct 3, 2026, 12:20 AM", 2026, 10, 3, 0, 20),
        ("Oct 3, 2026, 12:20 PM", 2026, 10, 3, 12, 20),
        ("3 oct 2026, 5:30 p. m.", 2026, 10, 3, 17, 30),
    ])
    func localised(text: String, year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        #expect(parser.date(from: text, order: nil) == date(year, month, day, hour, minute))
    }

    @Test("Narrow no-break spaces before AM/PM, as current ICU writes them")
    func narrowSpace() {
        #expect(parser.date(from: "Apr 9, 2024, 3:44\u{202F}PM", order: nil) == date(2024, 4, 9, 15, 44))
        #expect(parser.date(from: "Apr\u{00A0}9, 2024, 3:44 PM", order: nil) == date(2024, 4, 9, 15, 44))
        // Spanish 12-hour times as Foundation and browsers write them.
        #expect(parser.date(from: "3 oct 2026, 5:30\u{202F}p.\u{00A0}m.", order: nil) == date(2026, 10, 3, 17, 30))
        #expect(parser.date(from: "3 oct 2026, 9:05\u{00A0}a.\u{00A0}m.", order: nil) == date(2026, 10, 3, 9, 5))
    }

    @Test("Values that carry a zone are not wall-clock time")
    func zones() {
        let utc = ImportFixture.calendar(.gmt)
        let fitbod = utc.date(from: DateComponents(year: 2022, month: 1, day: 5, hour: 22, minute: 6, second: 49))
        #expect(parser.date(from: "2022-01-05 22:06:49 +0000", order: nil) == fitbod)
        let liftosaur = utc.date(from: DateComponents(year: 2024, month: 7, day: 18, hour: 5, minute: 2, second: 29, nanosecond: 801_000_000))
        let parsedLiftosaur = parser.date(from: "2024-07-18T05:02:29.801Z", order: nil)
        #expect(abs((parsedLiftosaur?.timeIntervalSince1970 ?? 0) - (liftosaur?.timeIntervalSince1970 ?? 1)) < 0.001)
        let offset = utc.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 7))
        #expect(parser.date(from: "2025-06-01 09:00 +02:00", order: nil) == offset)
        #expect(parser.date(from: "2025-06-01T09:00:00+0200", order: nil) == offset)
        #expect(parser.date(from: "2025-06-01 07:00 UTC", order: nil) == offset)
    }

    @Test("The same wall-clock text means a different instant in another zone")
    func wallClockFollowsZone() {
        let kolkata = ImportDateParser(timeZone: TimeZone(identifier: "Asia/Kolkata") ?? .gmt)
        let losAngeles = ImportDateParser(timeZone: TimeZone(identifier: "America/Los_Angeles") ?? .gmt)
        let first = kolkata.date(from: "15 Sep 2025, 07:48", order: nil)
        let second = losAngeles.date(from: "15 Sep 2025, 07:48", order: nil)
        #expect(first != nil && second != nil)
        #expect((second?.timeIntervalSince1970 ?? 0) - (first?.timeIntervalSince1970 ?? 0) == 12.5 * 3_600)
    }

    @Test("Medium dates with short times round-trip in many locales", arguments: [
        "en_GB", "en_US", "es_MX", "es_US", "it_IT", "de_DE", "fr_FR", "es_ES", "pt_BR", "nl_NL", "sv_SE", "pl_PL", "tr_TR", "ru_RU", "ja_JP", "ko_KR", "zh_CN", "nb_NO", "da_DK",
    ])
    func roundTrip(localeIdentifier: String) {
        let locale = Locale(identifier: localeIdentifier)
        for (month, day, hour, minute) in [(1, 20, 12, 0), (9, 1, 17, 5), (12, 31, 6, 59), (5, 9, 0, 30)] {
            let original = date(2026, month, day, hour, minute)
            let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: ImportFixture.calendar(zone), timeZone: zone)
            let text = original.formatted(style)
            #expect(parser.date(from: text, order: nil) == original, "\(localeIdentifier): \(text)")
        }
    }

    @Test("A value above 12 settles a numeric column's order")
    func orderFromColumn() {
        let dayFirst = parser.detect(["03/12/2023 11:25", "14/12/2023 08:00", "03/01/2024 10:00"])
        #expect(dayFirst == .readable(DateReading(order: .dayMonthYear, wasChosen: false, sample: "03/12/2023 11:25")))
        #expect(parser.date(from: "03/12/2023 11:25", order: .dayMonthYear) == date(2023, 12, 3, 11, 25))

        let monthFirst = parser.detect(["03/12/2023 11:25", "12/14/2023 08:00"])
        guard case .readable(let reading) = monthFirst else {
            Issue.record("Expected a readable column")
            return
        }
        #expect(reading.order == .monthDayYear)
        #expect(parser.date(from: "03/12/2023 11:25", order: .monthDayYear) == date(2023, 3, 12, 11, 25))
    }

    @Test("A column that cannot tell asks for the order with a sample, then honours it")
    func ambiguous() {
        let values = ["03/12/2023 11:25", "04/12/2023 09:00", "05/05/2023 09:00"]
        #expect(parser.detect(values) == .needsDateOrder(sample: "03/12/2023 11:25"))
        // Unreadable alone without an order: nothing guessed, nothing falls back to "now".
        #expect(parser.date(from: "03/12/2023 11:25", order: nil) == nil)
        #expect(parser.detect(values, order: .monthDayYear) == .readable(DateReading(order: .monthDayYear, wasChosen: true, sample: "03/12/2023 11:25")))
        #expect(parser.date(from: "04/12/2023 09:00", order: .monthDayYear) == date(2023, 4, 12, 9))
        #expect(parser.date(from: "04/12/2023 09:00", order: .dayMonthYear) == date(2023, 12, 4, 9))
        #expect(parser.date(from: "04/12/2023 09:00", order: .yearMonthDay) == nil)
    }

    @Test("Same day and month everywhere reads either way; dots mean day first")
    func unambiguousShapes() {
        guard case .readable = parser.detect(["05/05/2023", "11/11/2024"]) else {
            Issue.record("Equal day and month should not ask")
            return
        }
        #expect(parser.detect(["03.12.2023", "04.11.2023"]) == .readable(DateReading(order: .dayMonthYear, wasChosen: false, sample: "03.12.2023")))
        #expect(parser.date(from: "03.12.2023", order: nil) == date(2023, 12, 3))
    }

    @Test("Columns of words it cannot read ask, then report unreadable dates")
    func unreadable() {
        #expect(parser.detect(["yesterday", "last week"]) == .needsDateOrder(sample: "yesterday"))
        #expect(parser.detect(["yesterday"], order: .dayMonthYear) == .unreadable(sample: "yesterday"))
        #expect(parser.date(from: "", order: nil) == nil)
        #expect(parser.date(from: "Workout", order: nil) == nil)
    }

    @Test("Impossible dates and times are rejected", arguments: [
        "2025-02-30 10:00", "31 Apr 2025, 10:00", "2025-01-10 25:00", "2025-01-10 10:61", "13/13/2025", "2025-13-01", "0 Jan 2025",
        "15 Sep 2025, 13:00 PM", "Sep 2025", "15 Sep, 07:48",
    ])
    func impossible(text: String) {
        #expect(parser.date(from: text, order: .dayMonthYear) == nil)
    }

    @Test("Danish time with a dot after the date")
    func dottedTime() {
        #expect(parser.date(from: "20. jan. 2025, 12.00", order: nil) == date(2025, 1, 20, 12, 0))
    }

    @Test("Month names: abbreviations, prefixes, and shared spellings")
    func monthNames() {
        let names = MonthNames.shared
        #expect(names.month(for: "sept") == 9)
        #expect(names.month(for: "Sept.") == 9)
        #expect(names.month(for: "janv") == 1)
        #expect(names.month(for: "août") == 8)
        #expect(names.month(for: "März") == 3)
        #expect(names.month(for: "mrt") == 3)
        #expect(names.month(for: "Şub") == 2)
        #expect(names.month(for: "сент") == 9)
        #expect(names.month(for: "ju") == nil)
        #expect(names.month(for: "workout") == nil)
    }

    @Test("Seconds are kept; whether a value names a time")
    func hasTime() {
        #expect(parser.date(from: "2026-03-02 17:45:10", order: nil) == date(2026, 3, 2, 17, 45, 10))
        #expect(ImportDateParser.hasTime("2025-03-04 18:10"))
        #expect(!ImportDateParser.hasTime("2025-03-04"))
    }
}
