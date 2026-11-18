// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Settings editing and defaults")
struct SettingsEditingTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }

    private func freshSettings() throws -> (ModelContext, AppSettings) {
        let context = try makeInMemoryContext()
        let settings = try AppSettings.current(in: context)
        settings.createdAt = t0
        settings.updatedAt = t0
        return (context, settings)
    }

    @Test(arguments: [
        ("en_US", WeightUnit.lb),
        ("es_US", .lb),
        ("en_GB", .kg),
        ("de_DE", .kg),
        ("en_IN", .kg),
        ("ja_JP", .kg),
        ("en_AU", .kg),
    ])
    func unitFollowsTheRegion(_ identifier: String, _ expected: WeightUnit) {
        #expect(WeightUnit.preferred(for: Locale(identifier: identifier)) == expected)
    }

    @Test func aMetricOverrideInTheUSGivesKilograms() {
        #expect(WeightUnit.preferred(for: Locale(identifier: "en_US@measure=metric")) == .kg)
    }

    @Test func setsTheUnitAndMarksTheRowEdited() throws {
        let (_, settings) = try freshSettings()
        SettingsEditing.setUnit(.kg, on: settings, now: t1)
        #expect(settings.updatedAt == t0)
        SettingsEditing.setUnit(.lb, on: settings, now: t1)
        #expect(settings.unit == .lb)
        #expect(settings.updatedAt == t1)
        #expect(settings.wasEdited)
    }

    @Test func anExplicitChoiceCountsEvenWhenUnchanged() throws {
        let (_, settings) = try freshSettings()
        #expect(!settings.wasEdited)
        SettingsEditing.setUnit(.kg, on: settings, now: t1, isExplicitChoice: true)
        #expect(settings.unit == .kg)
        #expect(settings.updatedAt == t1)
        #expect(settings.wasEdited)
    }

    @Test func defaultRestIsRoundedToFifteenSecondsWithinRange() throws {
        let (_, settings) = try freshSettings()
        SettingsEditing.setDefaultRest(90, on: settings, now: t1)
        #expect(settings.updatedAt == t0)
        SettingsEditing.setDefaultRest(130, on: settings, now: t1)
        #expect(settings.defaultRestSeconds == 135)
        #expect(settings.updatedAt == t1)
        SettingsEditing.setDefaultRest(5, on: settings, now: t1)
        #expect(settings.defaultRestSeconds == 15)
        SettingsEditing.setDefaultRest(5_000, on: settings, now: t1)
        #expect(settings.defaultRestSeconds == 600)
    }

    @Test func crownSensitivitiesAreSetSeparately() throws {
        let (_, settings) = try freshSettings()
        #expect(settings.weightCrownSensitivity == .normal)
        #expect(settings.repsCrownSensitivity == .normal)
        SettingsEditing.setWeightCrownSensitivity(.normal, on: settings, now: t1)
        #expect(settings.updatedAt == t0)
        SettingsEditing.setWeightCrownSensitivity(.slow, on: settings, now: t1)
        #expect(settings.weightCrownSensitivity == .slow)
        #expect(settings.repsCrownSensitivity == .normal)
        #expect(settings.updatedAt == t1)
        let t2 = t1.addingTimeInterval(60)
        SettingsEditing.setRepsCrownSensitivity(.fast, on: settings, now: t2)
        #expect(settings.repsCrownSensitivity == .fast)
        #expect(settings.updatedAt == t2)
    }

    @Test func unknownStoredSensitivityReadsAsNormal() throws {
        let (_, settings) = try freshSettings()
        settings.weightCrownSensitivityRaw = "ludicrous"
        #expect(settings.weightCrownSensitivity == .normal)
        #expect(CrownSensitivity(persisted: "") == .normal)
        #expect(CrownSensitivity.allCases.map(\.rawValue) == ["slow", "normal", "fast"])
    }

    @Test func editedSensitivitiesWinWhenSyncMergesRows() throws {
        let context = try makeInMemoryContext()
        let phone = AppSettings()
        phone.createdAt = t0
        phone.updatedAt = t0
        context.insert(phone)
        SettingsEditing.setRepsCrownSensitivity(.slow, on: phone, now: t1)
        let watch = AppSettings()
        watch.createdAt = t0.addingTimeInterval(30)
        watch.updatedAt = watch.createdAt
        context.insert(watch)
        try context.save()

        let merged = try AppSettings.current(in: context)

        #expect(merged.repsCrownSensitivity == .slow)
        #expect(merged.weightCrownSensitivity == .normal)
        #expect(try context.count(AppSettings.self) == 1)
    }
}
