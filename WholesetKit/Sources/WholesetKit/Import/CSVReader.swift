// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The text encoding a CSV file was decoded with.
public enum CSVTextEncoding: String, Sendable, Equatable {
    /// UTF-8, with or without a byte order mark.
    case utf8
    /// UTF-16 with a byte order mark (spreadsheet "Unicode text").
    case utf16
    /// Windows-1252: the bytes were not valid UTF-8.
    case windows1252
    /// ISO Latin-1: the bytes were neither UTF-8 nor Windows-1252.
    case latin1

    /// Whether the file was not UTF-8, so accented letters may read differently than intended.
    public var isFallback: Bool {
        self == .windows1252 || self == .latin1
    }
}

/// One record of a CSV file.
public struct CSVRow: Sendable, Equatable {
    /// The record's fields, unquoted.
    public let fields: [String]
    /// The 1-based line of the file on which the record starts.
    public let line: Int
    /// Where the record's text sits in ``CSVTable/text``, as UTF-8 offsets.
    let range: Range<Int>

    /// Creates a row (tests).
    public init(fields: [String], line: Int) {
        self.fields = fields
        self.line = line
        self.range = 0..<0
    }

    init(fields: [String], line: Int, range: Range<Int>) {
        self.fields = fields
        self.line = line
        self.range = range
    }

    /// The field at `index`, or an empty string when the row is shorter.
    public subscript(index: Int) -> String {
        fields.indices.contains(index) ? fields[index] : ""
    }

    /// The field at `index` with surrounding whitespace removed; empty when absent.
    public func trimmed(_ index: Int?) -> String {
        guard let index else { return "" }
        return self[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A CSV file read into a header and rows.
public struct CSVTable: Sendable {
    /// The first non-blank record.
    public let header: CSVHeader
    /// Every later record that is not blank, in file order.
    public let rows: [CSVRow]
    /// The field separator found in the header line: `,`, `;` or a tab.
    public let delimiter: Character
    /// How the bytes were decoded.
    public let encoding: CSVTextEncoding
    /// Whether the file started with a byte order mark (which is never part of the data).
    public let hadByteOrderMark: Bool
    /// Lines of records whose field count differs from the header's. Missing trailing
    /// fields read as empty; extra fields are ignored.
    public let raggedLines: [Int]
    /// Records that a spreadsheet had wrapped in one extra pair of quotes, read again as
    /// separate fields.
    public let unwrappedRecordCount: Int
    /// The line of a quote that was never closed (the rest of the file became one field).
    public let unterminatedQuoteLine: Int?
    /// The decoded text as UTF-8, for ``rawText(of:)``.
    let text: [UInt8]

    /// The record's text as it appears in the file, without its line break.
    public func rawText(of row: CSVRow) -> String {
        guard !row.range.isEmpty, row.range.upperBound <= text.count else {
            return row.fields.joined(separator: String(delimiter))
        }
        return String(decoding: text[row.range], as: UTF8.self)
    }
}

/// Column names of a CSV header, looked up by name rather than position.
///
/// Names compare case-insensitively, with surrounding whitespace removed and inner runs of
/// whitespace collapsed, so `" Weight  (kg)"` and `"weight (kg)"` are the same column.
public struct CSVHeader: Sendable, Equatable {
    /// The names as written (trimmed).
    public let names: [String]
    /// The comparison keys, by position.
    let keys: [String]

    /// Creates a header from field values.
    public init(_ names: [String]) {
        let trimmed = names.map { $0.trimmingCharacters(in: CSVHeader.trimmedCharacters) }
        self.names = trimmed
        self.keys = trimmed.map(CSVHeader.key)
    }

    /// The comparison key of a column name.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: trimmedCharacters)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let trimmedCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    /// The number of columns.
    public var count: Int { names.count }

    /// The position of the first column named `name`.
    public func index(of name: String) -> Int? {
        keys.firstIndex(of: Self.key(name))
    }

    /// The position of the first column with any of `names`, tried in order.
    public func index(ofAny names: [String]) -> Int? {
        for name in names {
            if let index = index(of: name) { return index }
        }
        return nil
    }

    /// Whether a column is named `name`.
    public func contains(_ name: String) -> Bool {
        index(of: name) != nil
    }

    /// Whether every one of `names` is a column.
    public func containsAll(_ names: [String]) -> Bool {
        names.allSatisfy(contains)
    }
}

/// Reads CSV files (RFC 4180) as exported by workout apps and spreadsheets.
///
/// - **Decoding**: a UTF-8 byte order mark is dropped; UTF-16 with a byte order mark is
///   read; otherwise the bytes must be valid UTF-8, else they are read as Windows-1252 (or
///   ISO Latin-1 for the five bytes Windows-1252 leaves undefined). The table says which.
/// - **Delimiter**: the one a spreadsheet's `sep=;` first line declares, else whichever of
///   `,`, `;` and tab occurs most often in the header line, outside quotes; a comma when none does.
/// - **Quoting**: fields may be quoted; `""` inside quotes is one quote; quoted fields may
///   hold delimiters and line breaks (CRLF and CR inside them become LF). Text after a closing
///   quote is kept. A quote that is never closed takes the rest of the file and is reported.
/// - **Lines**: CRLF, LF and CR all end a record; blank lines (and rows of nothing but
///   delimiters) are skipped. Each row keeps the 1-based line it starts on.
/// - **Ragged rows** with fewer or more fields than the header are kept and reported.
///   A record a spreadsheet wrapped in quotes as a whole is split again.
public enum CSVReader {
    /// Why a file could not be read as CSV.
    public enum ReadError: Error, Equatable, Sendable {
        /// The file has no header line.
        case empty
        /// The file holds binary data rather than text.
        case notText
    }

    private static let quote = UInt8(ascii: "\"")
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let candidates: [UInt8] = [UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "\t")]

    /// Reads `data` as a CSV table.
    public static func read(_ data: Data) throws(ReadError) -> CSVTable {
        let (bytes, encoding, hadBOM) = try decode(data)
        let delimiter: UInt8
        var parser: Parser
        if let (declared, bodyStart) = declaredDelimiter(bytes) {
            delimiter = declared
            parser = Parser(bytes: bytes, delimiter: declared, start: bodyStart, line: 2)
        } else {
            delimiter = sniffDelimiter(bytes)
            parser = Parser(bytes: bytes, delimiter: delimiter)
        }

        var header: [String]?
        var rows: [CSVRow] = []
        var ragged: [Int] = []
        var unwrapped = 0
        while let record = parser.next() {
            if record.isBlank { continue }
            guard let names = header else {
                header = record.fields
                continue
            }
            var fields = record.fields
            if names.count > 1, fields.count == 1, fields[0].utf8.contains(delimiter) {
                var inner = Parser(bytes: Array(fields[0].utf8), delimiter: delimiter)
                if let reparsed = inner.next(), reparsed.fields.count > 1 {
                    fields = reparsed.fields
                    unwrapped += 1
                }
            }
            if fields.count != names.count {
                ragged.append(record.line)
            }
            rows.append(CSVRow(fields: fields, line: record.line, range: record.range))
        }
        guard let names = header else { throw .empty }
        return CSVTable(
            header: CSVHeader(names),
            rows: rows,
            delimiter: Character(Unicode.Scalar(delimiter)),
            encoding: encoding,
            hadByteOrderMark: hadBOM,
            raggedLines: ragged,
            unwrappedRecordCount: unwrapped,
            unterminatedQuoteLine: parser.unterminatedQuoteLine,
            text: bytes
        )
    }

    // MARK: Decoding

    /// The file's text as UTF-8 bytes, without a byte order mark.
    static func decode(_ data: Data) throws(ReadError) -> ([UInt8], CSVTextEncoding, Bool) {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = Array(bytes.dropFirst(3))
            if let text = String(validating: body, as: UTF8.self) {
                return (Array(text.utf8), .utf8, true)
            }
            return (try fallback(Data(body)), .windows1252, true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            let encoding: String.Encoding = bytes[0] == 0xFF ? .utf16LittleEndian : .utf16BigEndian
            guard let text = String(data: Data(bytes.dropFirst(2)), encoding: encoding) else { throw .notText }
            return (Array(text.utf8), .utf16, true)
        }
        if bytes.prefix(4_096).contains(0) { throw .notText }
        if String(validating: bytes, as: UTF8.self) != nil {
            return (bytes, .utf8, false)
        }
        if let text = String(data: data, encoding: .windowsCP1252) {
            return (Array(text.utf8), .windows1252, false)
        }
        guard let text = String(data: data, encoding: .isoLatin1) else { throw .notText }
        return (Array(text.utf8), .latin1, false)
    }

    private static func fallback(_ data: Data) throws(ReadError) -> [UInt8] {
        if let text = String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) {
            return Array(text.utf8)
        }
        throw .notText
    }

    // MARK: Delimiter

    /// Excel's `sep=;` first line: the delimiter it declares and where the next line starts.
    static func declaredDelimiter(_ bytes: [UInt8]) -> (UInt8, Int)? {
        guard bytes.count >= 5,
              Array(bytes.prefix(4)).map({ $0 | 0x20 }) == Array("sep=".utf8) else { return nil }
        let declared = bytes[4]
        var index = 5
        guard index == bytes.count || bytes[index] == carriageReturn || bytes[index] == lineFeed else { return nil }
        if index < bytes.count, bytes[index] == carriageReturn { index += 1 }
        if index < bytes.count, bytes[index] == lineFeed { index += 1 }
        return (declared, index)
    }

    /// The most frequent candidate delimiter in the first non-blank line, outside quotes.
    static func sniffDelimiter(_ bytes: [UInt8]) -> UInt8 {
        var counts: [UInt8: Int] = [:]
        var inQuotes = false
        var seenContent = false
        for byte in bytes {
            if byte == quote {
                inQuotes.toggle()
                seenContent = true
                continue
            }
            if !inQuotes, byte == lineFeed || byte == carriageReturn {
                if seenContent { break }
                continue
            }
            seenContent = true
            if !inQuotes, candidates.contains(byte) {
                counts[byte, default: 0] += 1
            }
        }
        var best = candidates[0]
        var bestCount = 0
        for candidate in candidates where counts[candidate, default: 0] > bestCount {
            best = candidate
            bestCount = counts[candidate, default: 0]
        }
        return best
    }

    // MARK: Parsing

    /// One record as the parser found it.
    struct Record {
        var fields: [String]
        var line: Int
        var range: Range<Int>
        /// A line with nothing but whitespace and delimiters (spreadsheets leave `,,,,` rows).
        var isBlank: Bool {
            fields.allSatisfy { $0.allSatisfy(\.isWhitespace) }
        }
    }

    /// Splits bytes into records.
    struct Parser {
        let bytes: [UInt8]
        let delimiter: UInt8
        private var position = 0
        private var line = 1
        private(set) var unterminatedQuoteLine: Int?

        init(bytes: [UInt8], delimiter: UInt8, start: Int = 0, line: Int = 1) {
            self.bytes = bytes
            self.delimiter = delimiter
            self.position = start
            self.line = line
        }

        /// The next record, or `nil` at the end.
        mutating func next() -> Record? {
            guard position < bytes.count else { return nil }
            let start = position
            let startLine = line
            var fields: [String] = []
            var buffer: [UInt8] = []
            while true {
                buffer.removeAll(keepingCapacity: true)
                if position < bytes.count, bytes[position] == CSVReader.quote {
                    readQuoted(into: &buffer)
                    fields.append(String(decoding: buffer, as: UTF8.self))
                } else {
                    let fieldStart = position
                    while position < bytes.count, bytes[position] != delimiter,
                          bytes[position] != CSVReader.lineFeed, bytes[position] != CSVReader.carriageReturn {
                        position += 1
                    }
                    fields.append(String(decoding: bytes[fieldStart..<position], as: UTF8.self))
                }
                // Now at a delimiter, a line break or the end.
                if position < bytes.count, bytes[position] == delimiter {
                    position += 1
                    continue
                }
                let end = position
                consumeLineBreak()
                return Record(fields: fields, line: startLine, range: start..<end)
            }
        }

        /// Reads a quoted field starting at its opening quote, plus anything up to the next
        /// delimiter or line break.
        private mutating func readQuoted(into buffer: inout [UInt8]) {
            let quoteLine = line
            position += 1
            while position < bytes.count {
                let byte = bytes[position]
                if byte == CSVReader.quote {
                    if position + 1 < bytes.count, bytes[position + 1] == CSVReader.quote {
                        buffer.append(CSVReader.quote)
                        position += 2
                        continue
                    }
                    position += 1
                    // Lenient: keep stray text after the closing quote.
                    while position < bytes.count, bytes[position] != delimiter,
                          bytes[position] != CSVReader.lineFeed, bytes[position] != CSVReader.carriageReturn {
                        buffer.append(bytes[position])
                        position += 1
                    }
                    return
                }
                if byte == CSVReader.carriageReturn {
                    buffer.append(CSVReader.lineFeed)
                    position += 1
                    if position < bytes.count, bytes[position] == CSVReader.lineFeed { position += 1 }
                    line += 1
                    continue
                }
                if byte == CSVReader.lineFeed { line += 1 }
                buffer.append(byte)
                position += 1
            }
            unterminatedQuoteLine = unterminatedQuoteLine ?? quoteLine
        }

        private mutating func consumeLineBreak() {
            guard position < bytes.count else { return }
            if bytes[position] == CSVReader.carriageReturn {
                position += 1
                if position < bytes.count, bytes[position] == CSVReader.lineFeed { position += 1 }
                line += 1
            } else if bytes[position] == CSVReader.lineFeed {
                position += 1
                line += 1
            }
        }
    }
}
