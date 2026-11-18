// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: CSV reader")
struct CSVReaderTests {
    private func read(_ text: String) throws -> CSVTable {
        try CSVReader.read(Data(text.utf8))
    }

    @Test("Reads a header and rows with their line numbers")
    func basic() throws {
        let table = try read("a,b,c\n1,2,3\n4,5,6\n")
        #expect(table.header.names == ["a", "b", "c"])
        #expect(table.rows.map(\.fields) == [["1", "2", "3"], ["4", "5", "6"]])
        #expect(table.rows.map(\.line) == [2, 3])
        #expect(table.delimiter == ",")
        #expect(table.encoding == .utf8)
        #expect(!table.hadByteOrderMark)
    }

    @Test("Strips a UTF-8 byte order mark")
    func byteOrderMark() throws {
        let table = try CSVReader.read(Data([0xEF, 0xBB, 0xBF]) + Data("Date,Exercise\n2025-01-01,Squat\n".utf8))
        #expect(table.hadByteOrderMark)
        #expect(table.header.names == ["Date", "Exercise"])
        #expect(table.header.index(of: "date") == 0)
    }

    @Test("Falls back to Windows-1252 when the bytes are not UTF-8, and says so")
    func windows1252() throws {
        // "Exercise\nCurl café" with é as the single byte 0xE9.
        var bytes = Array("Exercise,Note\nCurl,caf".utf8)
        bytes.append(0xE9)
        bytes += Array("\n".utf8)
        let table = try CSVReader.read(Data(bytes))
        #expect(table.encoding == .windows1252)
        #expect(table.encoding.isFallback)
        #expect(table.rows.first?.fields == ["Curl", "café"])
    }

    @Test("Reads UTF-16 with a byte order mark")
    func utf16() throws {
        var data = Data([0xFF, 0xFE])
        data.append(try #require("A\tB\n1\t2\n".data(using: .utf16LittleEndian)))
        let table = try CSVReader.read(data)
        #expect(table.encoding == .utf16)
        #expect(table.delimiter == "\t")
        #expect(table.rows.first?.fields == ["1", "2"])
    }

    @Test("Sniffs the delimiter from the header, outside quotes", arguments: [
        ("a;b;c\n1;2;3\n", Character(";")),
        ("a\tb\tc\n1\t2\t3\n", Character("\t")),
        ("\"a;x\",b,c\n1,2,3\n", Character(",")),
        ("\"a,x\";b;c\n1;2;3\n", Character(";")),
        ("single\nvalue\n", Character(",")),
    ])
    func delimiter(text: String, expected: Character) throws {
        #expect(try read(text).delimiter == expected)
    }

    @Test("A spreadsheet's sep= first line declares the delimiter and is not the header", arguments: ["sep=;\n", "SEP=;\r\n"])
    func declaredSeparator(first: String) throws {
        let table = try read(first + "Date;Exercise,Variant;Reps\n2025-01-01;Squat,High Bar;5\n")
        #expect(table.delimiter == ";")
        #expect(table.header.names == ["Date", "Exercise,Variant", "Reps"])
        #expect(table.rows.first?.fields == ["2025-01-01", "Squat,High Bar", "5"])
        #expect(table.rows.first?.line == 3)
    }

    @Test("Quoted fields keep delimiters, doubled quotes and line breaks")
    func quoting() throws {
        let table = try read("name,note,n\n\"Squat, high bar\",\"said \"\"easy\"\"\",1\n\"Row\",\"line one\r\nline two\",2\n\"Dip\",x,3\n")
        #expect(table.rows[0].fields == ["Squat, high bar", "said \"easy\"", "1"])
        #expect(table.rows[1].fields == ["Row", "line one\nline two", "2"])
        // The embedded line break moves later rows down a line.
        #expect(table.rows.map(\.line) == [2, 3, 5])
    }

    @Test("CRLF, LF and CR line endings and trailing blank lines", arguments: ["\r\n", "\n", "\r"])
    func lineEndings(separator: String) throws {
        let text = ["a,b", "1,2", "3,4", "", ""].joined(separator: separator)
        let table = try read(text)
        #expect(table.rows.map(\.fields) == [["1", "2"], ["3", "4"]])
        #expect(table.rows.map(\.line) == [2, 3])
    }

    @Test("Blank lines and rows of nothing but delimiters are skipped")
    func blankRows() throws {
        let table = try read("\n\na,b\n\n1,2\n,\n , \n3,4")
        #expect(table.header.names == ["a", "b"])
        #expect(table.rows.map(\.fields) == [["1", "2"], ["3", "4"]])
        #expect(table.rows.map(\.line) == [5, 8])
    }

    @Test("Ragged rows are kept and reported")
    func ragged() throws {
        let table = try read("a,b,c\n1,2\n1,2,3,4\n1,2,3\n")
        #expect(table.raggedLines == [2, 3])
        #expect(table.rows[0][2].isEmpty)
        #expect(table.rows[1].fields.count == 4)
    }

    @Test("A quote that never closes takes the rest of the file and is reported")
    func unterminatedQuote() throws {
        let table = try read("a,b\n1,\"open\n2,3\n")
        #expect(table.unterminatedQuoteLine == 2)
        #expect(table.rows.count == 1)
        #expect(table.rows[0][1] == "open\n2,3\n")
    }

    @Test("A record wrapped in one extra pair of quotes is split again")
    func wrappedRecords() throws {
        let table = try read("Date;Name;Reps\n\"2019-01-01;\"\"Squat\"\";5\"\n")
        #expect(table.rows.first?.fields == ["2019-01-01", "Squat", "5"])
        #expect(table.unwrappedRecordCount == 1)
    }

    @Test("Raw text of a row is what the file says")
    func rawText() throws {
        let table = try read("a,b\n\"x, y\",2\n")
        #expect(table.rawText(of: table.rows[0]) == "\"x, y\",2")
    }

    @Test("Empty files and binary files are refused")
    func refusals() throws {
        #expect(throws: CSVReader.ReadError.empty) { try CSVReader.read(Data()) }
        #expect(throws: CSVReader.ReadError.empty) { try CSVReader.read(Data("\n\n  \n".utf8)) }
        #expect(throws: CSVReader.ReadError.notText) { try CSVReader.read(Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00])) }
    }

    @Test("Columns are found by name: case, spacing and position do not matter")
    func headerLookup() {
        let header = CSVHeader(["  Weight  (kg) ", "REPS", "\u{FEFF}Date"])
        #expect(header.index(of: "weight (kg)") == 0)
        #expect(header.index(of: "reps") == 1)
        #expect(header.index(of: "date") == 2)
        #expect(header.index(ofAny: ["missing", "Reps"]) == 1)
        #expect(header.index(of: "weight") == nil)
        #expect(header.names[0] == "Weight  (kg)")
    }

    @Test("Reads 20,000 rows correctly (time is printed, not asserted)")
    func largeFile() throws {
        var text = "\"title\",\"start_time\",\"exercise_title\",\"set_index\",\"weight_kg\",\"reps\",\"note\"\n"
        for index in 0..<20_000 {
            text += "\"Day \(index / 20)\",\"\(index / 20) Jan 2026\",\"Exercise \(index % 7)\",\(index % 5),\(60 + index % 40).5,\(index % 12 + 1),\"n, \"\"\(index)\"\"\"\n"
        }
        let data = Data(text.utf8)
        let started = ContinuousClock.now
        let table = try CSVReader.read(data)
        let elapsed = started.duration(to: .now)
        print("CSVReader: 20,000 rows (\(data.count / 1024) KB) in \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) ms")
        #expect(table.rows.count == 20_000)
        #expect(table.rows[19_999].fields[6] == "n, \"19999\"")
        #expect(table.rows[19_999].line == 20_001)
        #expect(table.raggedLines.isEmpty)
    }
}
