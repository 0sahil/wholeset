// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

/// Synthetic import fixtures and fixed time zones for import tests.
enum ImportFixture {
    /// A zone with daylight saving time, so tests do not depend on the machine's zone.
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .gmt

    /// A Gregorian calendar in `zone`.
    static func calendar(_ zone: TimeZone = berlin) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// Options reading wall-clock dates in Berlin.
    static func options(weightUnit: WeightUnit = .kg, dateOrder: DateOrder? = nil, mapping: GenericMapping? = nil) -> ImportOptions {
        ImportOptions(weightUnit: weightUnit, dateOrder: dateOrder, timeZone: berlin, calendar: calendar(), mapping: mapping)
    }

    /// The bytes of `Fixtures/<name>.csv`.
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// The fixture read as an import file.
    static func file(_ name: String) throws -> ImportFile {
        try ImportFile(data: data(name))
    }

    /// The fixture parsed; fails the test unless it parses.
    static func parse(_ name: String, options: ImportOptions = options()) throws -> ImportParseResult {
        try parse(file(name), options: options)
    }

    /// `file` parsed; fails the test unless it parses.
    static func parse(_ file: ImportFile, options: ImportOptions = options()) throws -> ImportParseResult {
        guard case .parsed(let result) = file.parse(options) else {
            Issue.record("Expected the file to parse")
            throw FixtureError.notParsed
        }
        return result
    }

    /// A date from wall-clock components in `zone`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, zone: TimeZone = berlin) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar(zone).date(from: parts) ?? .distantPast
    }

    /// CSV text as bytes.
    static func csv(_ text: String) -> Data {
        Data(text.utf8)
    }

    enum FixtureError: Error {
        case notParsed
    }
}

extension Double {
    /// Whether two weights agree to a millionth of a kilogram.
    func isClose(to other: Double?, tolerance: Double = 1e-6) -> Bool {
        guard let other else { return false }
        return abs(self - other) <= tolerance
    }
}
