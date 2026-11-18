// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Import: format detection")
struct ImportFormatDetectionTests {
    private func detect(_ header: String) throws -> ImportLayout {
        try ImportFormatDetector.detect(CSVReader.read(Data((header + "\n").utf8)).header)
    }

    @Test("Each known header layout is recognised", arguments: [
        // Hevy: quoted or not, either unit, optional muscle_group.
        ("\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_kg\",\"reps\",\"distance_km\",\"duration_seconds\",\"rpe\"", ImportLayout.hevy(weight: .kg)),
        ("title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_miles,duration_seconds,rpe,muscle_group", .hevy(weight: .lb)),
        // Strong 1a, with and without the note columns.
        ("Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE", .strongNoUnit),
        ("Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE", .strongNoUnit),
        // Strong 1b, semicolon and comma.
        ("Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration", .strongUnitColumn),
        ("Date,Workout Name,Exercise Name,Set Order,Weight,Weight Unit,Reps,RPE,Distance,Distance Unit,Seconds,Notes,Workout Notes,Workout Duration", .strongUnitColumn),
        // Strong 1c, kg and lbs.
        ("\"Workout #\";\"Date\";\"Workout Name\";\"Duration (sec)\";\"Exercise Name\";\"Set Order\";\"Weight (kg)\";\"Reps\";\"RPE\";\"Distance (meters)\";\"Seconds\";\"Notes\";\"Workout Notes\"", .strongNumbered(weight: .kg)),
        ("\"Workout #\";\"Date\";\"Workout Name\";\"Duration (sec)\";\"Exercise Name\";\"Set Order\";\"Weight (lbs)\";\"Reps\";\"RPE\";\"Distance (meters)\";\"Seconds\";\"Notes\";\"Workout Notes\"", .strongNumbered(weight: .lb)),
        // Strong 1d.
        ("Date;Workout Name;Exercise Name;Set Order;lbs;Reps;mi.;Seconds;Notes;Workout Notes", .strongUnitHeader(weight: .lb)),
        ("Date;Workout Name;Exercise Name;Set Order;kg;Reps;km;Seconds;Notes;Workout Notes", .strongUnitHeader(weight: .kg)),
        // FitNotes, all five generations.
        ("\"Date\",\"Exercise\",\"Category\",\"Weight (kgs)\",\"Reps\",\"Distance\",\"Distance Unit\",\"Time\"", .fitNotesUnitHeader(weight: .kg)),
        ("Date,Exercise,Category,Weight (kgs),Reps,Distance,Distance Unit,Time,Comment", .fitNotesUnitHeader(weight: .kg)),
        ("Date,Exercise,Category,Weight (lbs),Reps,Distance,Distance Unit,Time", .fitNotesUnitHeader(weight: .lb)),
        ("Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time,Comment", .fitNotesUnitColumn),
        ("Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,Distance Unit,Time", .fitNotesUnitColumn),
        // Fitbod.
        ("Date,Exercise,Reps,Weight(kg),Duration(s),Distance(m),Incline,Resistance,isWarmup,Note,multiplier", .fitbod),
        // StrongLifts, kg and lb, with × in the names.
        ("Date (yyyy/mm/dd),Workout,Workout Name,Program Name,Body Weight (KG),Exercise,Sets×Reps,Sets×Time,Top Set (Reps×KG),e1RM (KG),Reps,Volume (KG),Workout Volume (KG),Duration (hours),Start Time (h:mm),End Time (h:mm),Notes,Set 1 (Reps),Set 1 (KG),Set 2 (Reps),Set 2 (KG)", .strongLifts(weight: .kg)),
        ("Date (yyyy/mm/dd),Workout,Workout Name,Program Name,Body Weight (KG),Exercise,Sets×Reps,Sets×Time,Top Set (Reps×LB),e1RM (LB),Reps,Volume (LB),Workout Volume (LB),Duration (hours),Start Time (h:mm),End Time (h:mm),Notes,Set 1 (Reps),Set 1 (LB)", .strongLifts(weight: .lb)),
        // Liftosaur, both generations.
        ("Workout DateTime,Program,Day Name,Exercise,Is Warmup Set?,Required Reps,Completed Reps,RPE,Is AMRAP?,Weight Value,Weight Unit,Completed Reps Time,Target Muscles,Synergist Muscles,Notes", .liftosaur(isCurrent: false)),
        ("Workout DateTime, Program, Day Name, Exercise, Is Warmup Set?, Required Reps, Completed Reps, Is AMRAP?, Required RPE, Completed RPE, Log RPE?, Required Weight Value, Required Weight Unit, Completed Weight Value, Completed Weight Unit, Ask Weight?, Completed Reps Time, Target Muscles, Synergist Muscles, Notes", .liftosaur(isCurrent: true)),
    ])
    func recognised(header: String, expected: ImportLayout) throws {
        #expect(try detect(header) == expected)
    }

    @Test("Other headers are generic", arguments: [
        // FitNotes for iOS (out of scope): both weight columns and a Kind column.
        "Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,Distance,Distance Unit,Time,Notes,Kind",
        // A JEFIT export starts with a section marker.
        "### SETTING ##########################################",
        "When,Movement,Wt (lbs),Reps,Routine",
        // Hevy without a weight column is not a Hevy export.
        "title,start_time,exercise_title,set_index,reps",
    ])
    func generic(header: String) throws {
        #expect(try detect(header) == .generic)
    }

    @Test("Detection reads only the header: the file name and row values do not matter")
    func headerOnly() throws {
        let file = try ImportFixture.file("strong-1c")
        #expect(file.layout == .strongNumbered(weight: .kg))
        #expect(file.layout.format == .strong)
        #expect(file.layout.identifier == "strong-1c-kg")
    }

    @Test("Formats know their source, beta label and app name")
    func formatFacts() {
        #expect(ImportFormat.allCases.allSatisfy { $0.source.isImported })
        #expect(Set(ImportFormat.allCases.map(\.source)).count == ImportFormat.allCases.count)
        #expect(ImportFormat.allCases.filter(\.isBeta) == [.fitbod, .strongLifts, .liftosaur])
        #expect(ImportFormat.strongLifts.appName == "StrongLifts 5×5")
    }

    @Test("Units: from the header, from a column, or not in the file")
    func unitLocations() {
        #expect(ImportLayout.hevy(weight: .lb).headerWeightUnit == .lb)
        #expect(ImportLayout.fitbod.headerWeightUnit == .kg)
        #expect(ImportLayout.strongUnitColumn.hasUnitColumn)
        #expect(ImportLayout.liftosaur(isCurrent: true).hasUnitColumn)
        #expect(ImportLayout.strongNoUnit.headerWeightUnit == nil)
        #expect(!ImportLayout.strongNoUnit.hasUnitColumn)
    }
}
