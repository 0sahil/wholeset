// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("AppSettings single row")
struct AppSettingsTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try WholesetStore.makeContainer(inMemory: true))
    }

    private func insertSettings(
        in context: ModelContext,
        created: TimeInterval,
        updated: TimeInterval,
        unit: WeightUnit,
        rest: Int,
        id: UUID = UUID()
    ) -> AppSettings {
        let settings = AppSettings(unit: unit, defaultRestSeconds: rest)
        settings.id = id
        settings.createdAt = Date(timeIntervalSince1970: created)
        settings.updatedAt = Date(timeIntervalSince1970: updated)
        context.insert(settings)
        return settings
    }

    @Test func createsDefaultRowWhenMissing() throws {
        let context = try makeContext()
        let settings = try AppSettings.current(in: context)
        #expect(settings.unit == .kg)
        #expect(settings.defaultRestSeconds == 90)
        #expect(try context.count(AppSettings.self) == 1)
        #expect(!context.hasChanges)
    }

    @Test func returnsTheSameRowOnLaterCalls() throws {
        let context = try makeContext()
        let first = try AppSettings.current(in: context)
        first.unit = .lb
        let second = try AppSettings.current(in: context)
        #expect(first.id == second.id)
        #expect(second.unit == .lb)
        #expect(try context.count(AppSettings.self) == 1)
    }

    @Test func collapsesDuplicatesKeepingOldestRowAndNewestValues() throws {
        let context = try makeContext()
        let oldest = insertSettings(in: context, created: 100, updated: 100, unit: .kg, rest: 90)
        _ = insertSettings(in: context, created: 200, updated: 500, unit: .lb, rest: 150)
        _ = insertSettings(in: context, created: 300, updated: 300, unit: .kg, rest: 60)
        try context.save()

        let settings = try AppSettings.current(in: context)

        #expect(settings.id == oldest.id)
        #expect(settings.createdAt == Date(timeIntervalSince1970: 100))
        #expect(settings.unit == .lb)
        #expect(settings.defaultRestSeconds == 150)
        #expect(settings.updatedAt == Date(timeIntervalSince1970: 500))
        #expect(try context.count(AppSettings.self) == 1)
        #expect(!context.hasChanges)
    }

    @Test func freshDefaultRowNeverOverridesEditedValues() throws {
        let context = try makeContext()
        // The row synced from another device: created earlier, edited since.
        let synced = insertSettings(in: context, created: 100, updated: 200, unit: .lb, rest: 120)
        // The default row this device created before sync caught up: newer, never edited.
        _ = insertSettings(in: context, created: 300, updated: 300, unit: .kg, rest: 90)
        try context.save()

        let settings = try AppSettings.current(in: context)

        #expect(settings.id == synced.id)
        #expect(settings.unit == .lb)
        #expect(settings.defaultRestSeconds == 120)
        #expect(try context.count(AppSettings.self) == 1)
    }

    @Test func editsOnTheNewerRowWin() throws {
        let context = try makeContext()
        let older = insertSettings(in: context, created: 100, updated: 100, unit: .kg, rest: 90)
        _ = insertSettings(in: context, created: 300, updated: 400, unit: .lb, rest: 60)
        try context.save()

        let settings = try AppSettings.current(in: context)

        #expect(settings.id == older.id)
        #expect(settings.unit == .lb)
        #expect(settings.defaultRestSeconds == 60)
    }

    @Test func newRowsStartUnedited() {
        let settings = AppSettings()
        #expect(settings.updatedAt == settings.createdAt)
    }

    @Test func breaksTimestampTiesByIdentifier() throws {
        let context = try makeContext()
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001"))
        // Same timestamps on both rows: the survivor and the value source are picked by id.
        _ = insertSettings(in: context, created: 100, updated: 100, unit: .lb, rest: 45, id: highID)
        _ = insertSettings(in: context, created: 100, updated: 100, unit: .kg, rest: 75, id: lowID)
        try context.save()

        let settings = try AppSettings.current(in: context)

        #expect(settings.id == lowID)
        #expect(settings.unit == .lb)
        #expect(settings.defaultRestSeconds == 45)
        #expect(try context.count(AppSettings.self) == 1)
    }

    @Test func collapsedRowPersists() throws {
        try withTemporaryStoreURL { url in
            do {
                let context = try reopen(url)
                _ = insertSettings(in: context, created: 100, updated: 100, unit: .kg, rest: 90)
                _ = insertSettings(in: context, created: 200, updated: 200, unit: .lb, rest: 120)
                try context.save()
                _ = try AppSettings.current(in: context)
            }

            let context = try reopen(url)
            let rows = try context.all(AppSettings.self)
            #expect(rows.count == 1)
            #expect(rows.first?.unit == .lb)
            #expect(rows.first?.defaultRestSeconds == 120)
        }
    }
}
