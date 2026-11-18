// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The order of day, month and year in an all-numeric date.
public enum DateOrder: String, Sendable, CaseIterable, Identifiable {
    /// `20/01/2025`
    case dayMonthYear
    /// `01/20/2025`
    case monthDayYear
    /// `2025/01/20`
    case yearMonthDay

    public var id: String { rawValue }
}

/// Reads the dates workout apps write into their exports.
///
/// Exports write dates in many shapes: ISO-like (`2025-01-20 12:00:00`), with an offset or
/// `Z` (`2022-01-05 22:06:49 +0000`, `2024-07-18T05:02:29.801Z`), and, in Hevy's case, in the
/// app's language: `15 Sep 2025, 07:48`, `Apr 9, 2024, 3:44 PM`, `18 ago 2026, 12:27`,
/// `20.01.2025, 12:00`, `20 janv. 2025, 12:00`, `20 de jan. de 2025, 12:00`, `2025/01/20 12:00`,
/// `2025年1月20日 12:00` …
///
/// Rather than trying one fixed-format formatter per locale and pattern (which breaks on
/// punctuation such as narrow no-break spaces before "PM", trailing dots in abbreviations
/// or connecting words), a value is split into numbers, words and separators:
/// - **Time**: the last `H:mm`, `H:mm:ss` or `H:mm:ss.fff` (or `HH.mm` after the date, as
///   Danish writes it), with AM/PM markers (`PM`, `p. m.`, `午後`, `오후` …) anywhere.
/// - **Zone**: `Z`, `UTC`/`GMT` or a `+hhmm` / `+hh:mm` offset after the time; without one
///   the value is wall-clock time in ``timeZone``.
/// - **Date**: three numbers (year first, or year last), or two numbers and a month name.
///   Month names come from Foundation's own month symbols for English, Italian, German,
///   French, Spanish, Portuguese, Dutch, Swedish, Danish, Norwegian, Polish, Turkish and
///   Russian, compared without case, diacritics or dots, and also as a prefix of at least
///   three letters of a full month name (`sept`, `janv`, `juil`). Connecting words (`de`,
///   `à`, `at`, `г.`, `年` …) are skipped; any other word makes the value unreadable.
///
/// All-numeric dates with the year last (`03/12/2023`) can be day-first or month-first;
/// ``detect(_:order:)`` decides once for the whole column (a value above 12 settles it; dots
/// mean day-first) and asks for a ``DateOrder`` when the column cannot tell. Nothing ever
/// falls back to the current date: a value that cannot be read gives `nil`.
public struct ImportDateParser: Sendable {
    /// What ``detect(_:order:)`` found.
    public enum Detection: Sendable, Equatable {
        /// Dates can be read this way.
        case readable(DateReading)
        /// All-numeric dates whose order the values cannot tell: ask, then detect again with an order.
        case needsDateOrder(sample: String)
        /// No value could be read even with the given order.
        case unreadable(sample: String)
    }

    /// The zone of values that carry none.
    public let timeZone: TimeZone
    private let calendar: Calendar

    /// Creates a parser for wall-clock values in `timeZone`.
    ///
    /// - Parameter calendar: A Gregorian calendar (export files always write Gregorian
    ///   dates); its time zone is replaced by `timeZone`.
    public init(timeZone: TimeZone, calendar: Calendar = Calendar(identifier: .gregorian)) {
        var calendar = calendar.identifier == .gregorian ? calendar : Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.timeZone = timeZone
        self.calendar = calendar
    }

    // MARK: Detection

    /// Decides how to read a column of date values (every value is looked at once).
    ///
    /// - Parameter order: The caller's order for ambiguous all-numeric dates, after
    ///   ``Detection/needsDateOrder(sample:)``.
    public func detect(_ values: some Sequence<String>, order: DateOrder? = nil) -> Detection {
        var seen: Set<String> = []
        var firstReadable: String?
        var firstUnreadable: String?
        var ambiguous: String?
        var hasNumeric = false
        var dayFirstFits = true
        var monthFirstFits = true
        for value in values where seen.insert(value).inserted {
            guard let analysis = Self.analyze(value) else {
                if firstUnreadable == nil, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    firstUnreadable = value
                }
                continue
            }
            firstReadable = firstReadable ?? value
            guard case let .yearLast(first, second, _, dotted) = analysis.date else { continue }
            hasNumeric = true
            let dayFirst = Self.fits(day: first, month: second)
            let monthFirst = !dotted && Self.fits(day: second, month: first)
            if !dayFirst { dayFirstFits = false }
            if !monthFirst { monthFirstFits = false }
            if dayFirst, monthFirst, first != second, ambiguous == nil {
                ambiguous = value
            }
        }
        guard let sample = firstReadable else {
            let shown = firstUnreadable ?? ""
            return order == nil ? .needsDateOrder(sample: shown) : .unreadable(sample: shown)
        }
        guard hasNumeric else {
            return .readable(DateReading(order: nil, wasChosen: false, sample: sample))
        }
        if let order {
            return .readable(DateReading(order: order, wasChosen: true, sample: ambiguous ?? sample))
        }
        switch (dayFirstFits, monthFirstFits) {
        case (true, true):
            if let ambiguous { return .needsDateOrder(sample: ambiguous) }
            // Every value has the same day and month number: either order gives the same dates.
            return .readable(DateReading(order: .dayMonthYear, wasChosen: false, sample: sample))
        case (true, false):
            return .readable(DateReading(order: .dayMonthYear, wasChosen: false, sample: sample))
        case (false, true):
            return .readable(DateReading(order: .monthDayYear, wasChosen: false, sample: sample))
        case (false, false):
            return .needsDateOrder(sample: ambiguous ?? sample)
        }
    }

    /// The instant `text` stands for, or `nil` if it cannot be read.
    ///
    /// - Parameter order: How to read all-numeric dates with the year last; `nil` reads
    ///   them only when they are unambiguous (day above 12, or dots).
    public func date(from text: String, order: DateOrder?) -> Date? {
        guard let analysis = Self.analyze(text) else { return nil }
        let year, month, day: Int
        switch analysis.date {
        case let .fixed(y, m, d):
            (year, month, day) = (y, m, d)
        case let .yearLast(first, second, y, dotted):
            let dayFirst = Self.fits(day: first, month: second)
            let monthFirst = !dotted && Self.fits(day: second, month: first)
            switch order {
            case .dayMonthYear? where dayFirst, nil where dayFirst && (!monthFirst || first == second):
                (year, month, day) = (y, second, first)
            case .monthDayYear? where monthFirst, nil where monthFirst && !dayFirst:
                (year, month, day) = (y, first, second)
            default:
                return nil
            }
        }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = analysis.time?.hour ?? 0
        parts.minute = analysis.time?.minute ?? 0
        parts.second = analysis.time?.second ?? 0
        parts.nanosecond = analysis.time?.nanosecond ?? 0
        var calendar = calendar
        if let zone = analysis.zone { calendar.timeZone = zone }
        guard let date = calendar.date(from: parts) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// Whether the value names a time of day (not just a date).
    public static func hasTime(_ text: String) -> Bool {
        analyze(text)?.time != nil
    }

    private static func fits(day: Int, month: Int) -> Bool {
        (1...31).contains(day) && (1...12).contains(month)
    }

    // MARK: Analysis

    /// A value split into its date, time and zone.
    struct Analysis: Equatable {
        enum DatePart: Equatable {
            /// Year, month and day are known.
            case fixed(year: Int, month: Int, day: Int)
            /// Two numbers then the year; their order depends on the file.
            case yearLast(first: Int, second: Int, year: Int, dotted: Bool)
        }

        struct Time: Equatable {
            var hour: Int
            var minute: Int
            var second: Int
            var nanosecond: Int
        }

        var date: DatePart
        var time: Time?
        var zone: TimeZone?
    }

    enum Token: Equatable {
        case number(Int, digits: Int)
        case word(String)
        case symbol(Character)
        case space
    }

    static func analyze(_ text: String) -> Analysis? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }
        if let analysis = analyze(tokens, dottedTime: false) { return analysis }
        return analyze(tokens, dottedTime: true)
    }

    private static func analyze(_ tokens: [Token], dottedTime: Bool) -> Analysis? {
        var tokens = tokens
        var time: Analysis.Time?
        var zone: TimeZone?

        if let range = timeRange(in: tokens, dotted: dottedTime) {
            guard let parsed = timeValue(Array(tokens[range])) else { return nil }
            time = parsed
            var trailing = Array(tokens[range.upperBound...])
            if let (offset, consumed) = zoneValue(trailing) {
                zone = offset
                trailing.removeSubrange(consumed)
            }
            tokens = Array(tokens[..<range.lowerBound]) + trailing
        }

        var meridiem: Bool?
        var numbers: [(value: Int, digits: Int)] = []
        var separatorBeforeSecond: Character?
        var lastSymbol: Character?
        var month: Int?
        for token in tokens {
            switch token {
            case let .number(value, digits):
                if numbers.count == 1 { separatorBeforeSecond = lastSymbol }
                numbers.append((value, digits))
                lastSymbol = nil
            case .word(let word):
                if let isPM = meridiemWords[word] {
                    guard meridiem == nil else { return nil }
                    meridiem = isPM
                } else if fillerWords.contains(word) {
                    continue
                } else if let found = MonthNames.shared.month(for: word) {
                    guard month == nil else { return nil }
                    month = found
                } else {
                    return nil
                }
            case .symbol(let symbol):
                lastSymbol = symbol
            case .space:
                continue
            }
        }

        if let meridiem {
            guard var adjusted = time, (1...12).contains(adjusted.hour) else { return nil }
            if meridiem, adjusted.hour < 12 { adjusted.hour += 12 }
            if !meridiem, adjusted.hour == 12 { adjusted.hour = 0 }
            time = adjusted
        }

        let date: Analysis.DatePart
        if let month {
            guard numbers.count == 2 else { return nil }
            let fourDigit = numbers.indices.filter { numbers[$0].digits == 4 }
            let yearIndex: Int
            switch fourDigit.count {
            case 1: yearIndex = fourDigit[0]
            case 0: yearIndex = 1
            default: return nil
            }
            let day = numbers[1 - yearIndex].value
            guard numbers[1 - yearIndex].digits <= 2, let year = expandYear(numbers[yearIndex]) else { return nil }
            date = .fixed(year: year, month: month, day: day)
        } else {
            guard numbers.count == 3 else { return nil }
            if numbers[0].digits == 4 {
                guard numbers[1].digits <= 2, numbers[2].digits <= 2, let year = expandYear(numbers[0]) else { return nil }
                date = .fixed(year: year, month: numbers[1].value, day: numbers[2].value)
            } else if numbers[0].digits <= 2, numbers[1].digits <= 2, let year = expandYear(numbers[2]) {
                let first = numbers[0].value
                let second = numbers[1].value
                let dotted = separatorBeforeSecond == "."
                guard fits(day: first, month: second) || (!dotted && fits(day: second, month: first)) else { return nil }
                date = .yearLast(first: first, second: second, year: year, dotted: dotted)
            } else {
                return nil
            }
        }
        if case let .fixed(_, month, day) = date, !fits(day: day, month: month) { return nil }
        return Analysis(date: date, time: time, zone: zone)
    }

    /// A 4-digit year, or a 2-digit one (`25` → 2025, `98` → 1998), within 1900...2200.
    private static func expandYear(_ number: (value: Int, digits: Int)) -> Int? {
        let year: Int
        switch number.digits {
        case 4: year = number.value
        case 2: year = number.value + (number.value < 70 ? 2000 : 1900)
        default: return nil
        }
        return (1900...2200).contains(year) ? year : nil
    }

    /// The tokens of the last `H:mm[:ss[.fff]]` (or, when `dotted`, a final `H.mm[.ss]` after a space).
    private static func timeRange(in tokens: [Token], dotted: Bool) -> Range<Int>? {
        let separator: Character = dotted ? "." : ":"
        var found: Range<Int>?
        var index = 0
        while index + 2 < tokens.count {
            // "+02:00" is an offset, not a time.
            let isOffset = index > 0 && [Token.symbol("+"), .symbol("-"), .symbol("\u{2212}")].contains(tokens[index - 1])
            guard !isOffset, case let .number(_, hourDigits) = tokens[index], hourDigits <= 2,
                  tokens[index + 1] == .symbol(separator),
                  case let .number(_, minuteDigits) = tokens[index + 2], minuteDigits == 2 else {
                index += 1
                continue
            }
            var end = index + 3
            if end + 1 < tokens.count, tokens[end] == .symbol(separator),
               case let .number(_, secondDigits) = tokens[end + 1], secondDigits == 2 {
                end += 2
                if !dotted, end + 1 < tokens.count, tokens[end] == .symbol(".") || tokens[end] == .symbol(","),
                   case .number = tokens[end + 1] {
                    end += 2
                }
            }
            found = index..<end
            index = end
        }
        guard let found else { return nil }
        if dotted {
            // Only a time at the very end, after a space, e.g. "20. jan. 2025, 12.00".
            let rest = tokens[found.upperBound...].filter { $0 != .space }
            guard rest.isEmpty, found.lowerBound > 0, tokens[found.lowerBound - 1] == .space else { return nil }
        }
        return found
    }

    private static func timeValue(_ tokens: [Token]) -> Analysis.Time? {
        let numbers = tokens.compactMap { token -> (Int, Int)? in
            if case let .number(value, digits) = token { return (value, digits) }
            return nil
        }
        guard numbers.count >= 2 else { return nil }
        let hour = numbers[0].0
        let minute = numbers[1].0
        let second = numbers.count > 2 ? numbers[2].0 : 0
        var nanosecond = 0
        if numbers.count > 3 {
            let (fraction, digits) = numbers[3]
            let scale = digits < 9 ? Int(pow(10, Double(9 - digits))) : 1
            nanosecond = digits <= 9 ? fraction * scale : 0
        }
        guard (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
        return Analysis.Time(hour: hour, minute: minute, second: min(second, 59), nanosecond: nanosecond)
    }

    /// A zone at the start of `tokens` (after the time), and the tokens it used.
    private static func zoneValue(_ tokens: [Token]) -> (TimeZone, Range<Int>)? {
        var index = 0
        while index < tokens.count, tokens[index] == .space { index += 1 }
        guard index < tokens.count else { return nil }
        let start = index
        var isNamed = false
        if case .word(let word) = tokens[index] {
            if word == "z" { return (.gmt, start..<(index + 1)) }
            guard word == "utc" || word == "gmt" else { return nil }
            isNamed = true
            index += 1
        }
        guard index < tokens.count, case .symbol(let sign) = tokens[index], sign == "+" || sign == "-" || sign == "\u{2212}" else {
            return isNamed ? (.gmt, start..<index) : nil
        }
        index += 1
        guard index < tokens.count, case let .number(value, digits) = tokens[index] else { return nil }
        index += 1
        var hours: Int
        var minutes = 0
        switch digits {
        case 4:
            hours = value / 100
            minutes = value % 100
        case 1, 2:
            hours = value
            if index + 1 < tokens.count, tokens[index] == .symbol(":"), case let .number(more, 2) = tokens[index + 1] {
                minutes = more
                index += 2
            }
        default:
            return nil
        }
        guard hours <= 14, minutes < 60 else { return nil }
        if sign != "+" { hours = -hours; minutes = -minutes }
        guard let zone = TimeZone(secondsFromGMT: hours * 3_600 + minutes * 60) else { return nil }
        return (zone, start..<index)
    }

    // MARK: Tokens

    private static let meridiemWords: [String: Bool] = [
        "am": false, "pm": true,
        "午前": false, "午後": true, "오전": false, "오후": true, "上午": false, "下午": true,
    ]

    /// Words that connect parts of a date and are skipped.
    private static let fillerWords: Set<String> = [
        "de", "del", "a", "as", "at", "om", "um", "kl", "klo", "o", "g", "t", "le", "el", "the", "alle", "ore",
        "年", "月", "日", "년", "월", "일", "г",
    ]

    static func tokenize(_ text: String) -> [Token] {
        // Every kind of space (no-break, narrow no-break, thin …) as a plain one, so "p.\u{00A0}m."
        // and "5:30\u{202F}PM" read like "p. m." and "5:30 PM".
        var spaced = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            spaced.append(CharacterSet.whitespaces.contains(scalar) ? " " : scalar)
        }
        var normalized = String(spaced).lowercased(with: Locale(identifier: "en_US_POSIX"))
        for (variant, replacement) in [("a. m.", " am "), ("p. m.", " pm "), ("a.m.", " am "), ("p.m.", " pm ")] {
            normalized = normalized.replacingOccurrences(of: variant, with: replacement)
        }
        var tokens: [Token] = []
        var number = 0
        var digits = 0
        var word = ""
        func flushNumber() {
            guard digits > 0 else { return }
            tokens.append(.number(number, digits: digits))
            number = 0
            digits = 0
        }
        func flushWord() {
            guard !word.isEmpty else { return }
            tokens.append(.word(word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))))
            word = ""
        }
        for scalar in normalized.unicodeScalars {
            if ("0"..."9").contains(scalar) {
                flushWord()
                if digits < 9 { number = number * 10 + Int(scalar.value - 48) }
                digits += 1
            } else if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                flushNumber()
                word.unicodeScalars.append(scalar)
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushNumber()
                flushWord()
                if tokens.last != .space { tokens.append(.space) }
            } else {
                flushNumber()
                flushWord()
                tokens.append(.symbol(Character(scalar)))
            }
        }
        flushNumber()
        flushWord()
        while tokens.last == .space { tokens.removeLast() }
        while tokens.first == .space { tokens.removeFirst() }
        return tokens
    }
}

/// Month names in the languages exports are written in, from Foundation's locale data.
struct MonthNames: Sendable {
    static let shared = MonthNames()

    /// Locales whose month names are recognised.
    static let localeIdentifiers = [
        "en_US", "en_GB", "it_IT", "de_DE", "fr_FR", "es_ES", "pt_BR", "pt_PT", "nl_NL",
        "sv_SE", "da_DK", "nb_NO", "pl_PL", "tr_TR", "ru_RU",
    ]

    /// Every spelling (full and abbreviated) with its month; spellings two months share are left out.
    private let exact: [String: Int]
    /// Full month names, for prefix matches.
    private let full: [(name: String, month: Int)]

    init() {
        var exact: [String: Int] = [:]
        var conflicts: Set<String> = []
        var full: [(String, Int)] = []
        for identifier in Self.localeIdentifiers {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: identifier)
            let fullLists = [calendar.monthSymbols, calendar.standaloneMonthSymbols]
            let shortLists = [calendar.shortMonthSymbols, calendar.shortStandaloneMonthSymbols]
            for list in fullLists + shortLists {
                for (index, symbol) in list.enumerated() {
                    let key = Self.normalized(symbol)
                    guard !key.isEmpty else { continue }
                    if let existing = exact[key], existing != index + 1 { conflicts.insert(key) }
                    exact[key] = index + 1
                }
            }
            for list in fullLists {
                for (index, symbol) in list.enumerated() {
                    full.append((Self.normalized(symbol), index + 1))
                }
            }
        }
        for key in conflicts { exact.removeValue(forKey: key) }
        self.exact = exact
        self.full = full
    }

    /// Lower-cased, diacritics folded, dots removed.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The month (1–12) `word` names, if exactly one month fits.
    func month(for word: String) -> Int? {
        let key = Self.normalized(word)
        if let month = exact[key] { return month }
        guard key.count >= 3 else { return nil }
        let months = Set(full.filter { $0.name.hasPrefix(key) }.map(\.month))
        return months.count == 1 ? months.first : nil
    }
}
