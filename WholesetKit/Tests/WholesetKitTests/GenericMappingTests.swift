// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: generic CSV columns")
struct GenericMappingTests {
    private func table(_ text: String) throws -> CSVTable {
        try CSVReader.read(Data(text.utf8))
    }

    @Test("Roles are guessed from names and sample values")
    func suggested() throws {
        let file = try ImportFixture.file("generic")
        let mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows)
        #expect(mapping.roles == [.date, .exercise, .weight, .reps, .workoutName, .note, .setOrder, .ignore])
        #expect(mapping.isComplete)
        #expect(mapping.headerWeightUnit(in: file.table.header) == .lb)
    }

    @Test("Other common column names", arguments: [
        ("Datum,Exercise Name,Weight (kg),Repetitions,Workout,Notes", [ColumnRole.date, .exercise, .weight, .reps, .workoutName, .note]),
        ("Timestamp,Lift,Load,Rep,Session Title,Comment,Set #,Duration", [.date, .exercise, .weight, .reps, .workoutName, .note, .setOrder, .workoutDuration]),
        ("date,exercise,reps,weight,weight unit,notes", [.date, .exercise, .reps, .weight, .weightUnit, .note]),
        ("Day,Exercise,Category,Reps,Body Weight", [.date, .exercise, .ignore, .reps, .ignore]),
    ])
    func names(header: String, expected: [ColumnRole]) throws {
        let table = try table(header + "\n")
        #expect(GenericMapping.suggested(header: table.header, sampleRows: table.rows).roles == expected)
    }

    @Test("Names and samples together: a vague date name, a day that is not a date, remarks")
    func namesWithSamples() throws {
        let table = try table("Logged On,Lift,Load (lb),Reps,Program Day,Remarks\n2026-09-01 17:30,Front squat,155,5,Day 1,easy\n")
        let mapping = GenericMapping.suggested(header: table.header, sampleRows: table.rows)
        #expect(mapping.roles == [.date, .exercise, .weight, .reps, .workoutName, .note])
        #expect(mapping.headerWeightUnit(in: table.header) == .lb)
    }

    @Test("A date column is found by its values when its name says nothing")
    func dateByValue() throws {
        let table = try table("Col A,Exercise,Reps\n2025-03-04 18:10,Squat,5\n")
        #expect(GenericMapping.suggested(header: table.header, sampleRows: table.rows).column(for: .date) == 0)
    }

    @Test("A column named like a date whose values are not dates is not the date")
    func dateNameButNoDate() throws {
        let table = try table("Day,Exercise,Reps\nLeg day,Squat,5\n")
        #expect(GenericMapping.suggested(header: table.header, sampleRows: table.rows).column(for: .date) == nil)
    }

    @Test("Giving a role to a column takes it from the column that had it")
    func assign() {
        var mapping = GenericMapping(roles: [.date, .exercise, .reps, .ignore])
        mapping.assign(.exercise, toColumn: 3)
        #expect(mapping.roles == [.date, .ignore, .reps, .exercise])
        mapping.assign(.ignore, toColumn: 0)
        #expect(mapping.missingRoles == [.date])
        #expect(!mapping.isComplete)
        mapping.assign(.date, toColumn: 9)
        #expect(mapping.roles.count == 4)
    }

    @Test("A repeated role keeps its first column")
    func repeatedRole() {
        #expect(GenericMapping(roles: [.date, .date, .reps]).roles == [.date, .ignore, .reps])
    }

    @Test("Each column's sample is its first non-empty value")
    func samples() throws {
        let table = try table("a,b,c\n1,,\n2,x,\n")
        #expect(GenericMapping.samples(columnCount: 3, rows: table.rows) == ["1", "x", ""])
    }

    @Test("The weight unit comes from a unit column, the weight column's name, or the choice")
    func unitSource() throws {
        let header = CSVHeader(["Date", "Exercise", "Weight (kg)", "Unit", "Reps"])
        #expect(GenericMapping(roles: [.date, .exercise, .weight, .weightUnit, .reps]).weightUnitSource(in: header, chosen: .lb) == .column)
        #expect(GenericMapping(roles: [.date, .exercise, .weight, .ignore, .reps]).weightUnitSource(in: header, chosen: .lb) == .header(.kg))
        let plain = CSVHeader(["Date", "Exercise", "Weight", "Reps"])
        #expect(GenericMapping(roles: [.date, .exercise, .weight, .reps]).weightUnitSource(in: plain, chosen: .lb) == .chosen(.lb))
    }
}
