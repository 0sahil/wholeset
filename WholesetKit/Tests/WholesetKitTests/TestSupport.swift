// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
@testable import WholesetKit

/// Runs `body` with a SQLite store URL inside a fresh temporary directory, then
/// deletes the directory.
func withTemporaryStoreURL<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "WholesetKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory.appending(path: "Test.store"))
}

/// Opens a new on-disk container for `url`, so reads come from SQLite rather than
/// from objects cached by the container that wrote them.
func reopen(_ url: URL) throws -> ModelContext {
    ModelContext(try WholesetStore.makeContainer(url: url))
}

/// A fresh in-memory context.
func makeInMemoryContext() throws -> ModelContext {
    ModelContext(try WholesetStore.makeContainer(inMemory: true))
}

/// A clock whose time only moves when a test moves it.
final class TestClock {
    var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.date = date
    }

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }

    /// A closure reading the current test time, for injection.
    var now: () -> Date {
        { [unowned self] in self.date }
    }
}

/// A Gregorian calendar in UTC, so weekday maths does not depend on the test machine.
var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}

/// Inserts an exercise, a routine and its items. Each spec is (name, equipment, sets, repLow, repHigh, rest).
@discardableResult
func insertRoutine(
    _ name: String,
    sortIndex: Int = 0,
    items: [(String, Equipment, Int, Int, Int, Int?)],
    in context: ModelContext
) -> Routine {
    let routine = Routine(name: name, sortIndex: sortIndex)
    context.insert(routine)
    for (order, spec) in items.enumerated() {
        let exercise = Exercise(name: spec.0, equipment: spec.1)
        context.insert(exercise)
        let item = RoutineItem(order: order, targetSets: spec.2, repLow: spec.3, repHigh: spec.4, restSeconds: spec.5)
        context.insert(item)
        item.routine = routine
        item.exercise = exercise
    }
    return routine
}

extension ModelContext {
    /// Inserts several models of possibly different types.
    func insertAll(_ models: any PersistentModel...) {
        for model in models {
            insert(model)
        }
    }

    /// Fetches every model of type `T`.
    func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try fetch(FetchDescriptor<T>())
    }

    /// Counts every model of type `T`.
    func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try fetchCount(FetchDescriptor<T>())
    }
}
