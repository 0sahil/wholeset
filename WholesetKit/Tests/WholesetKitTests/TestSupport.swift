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
