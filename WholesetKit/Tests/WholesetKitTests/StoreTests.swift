// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

@Suite("Store setup")
struct StoreTests {
    @Test func inMemoryContainerNeverUsesCloudKit() throws {
        let container = try WholesetStore.makeContainer(inMemory: true, cloudKit: true)
        let configuration = try #require(container.configurations.first)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }

    @Test func localContainerUsesGivenURLWithoutCloudKit() throws {
        try withTemporaryStoreURL { url in
            let container = try WholesetStore.makeContainer(url: url)
            let configuration = try #require(container.configurations.first)
            #expect(configuration.url == url)
            #expect(!configuration.isStoredInMemoryOnly)
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
    }

    @Test func loadOpensLocalStoreWhenCloudKitIsOff() throws {
        try withTemporaryStoreURL { url in
            let result = WholesetStore.loadAppContainer(cloudKit: false, url: url)
            #expect(result.mode == .local)
            #expect(result.container?.configurations.first?.url == url)
        }
    }

    @Test func loadFallsBackToMemoryWhenDiskStoreCannotOpen() throws {
        try withTemporaryStoreURL { url in
            // A regular file where the store's parent directory should be.
            let blocker = url.deletingLastPathComponent().appending(path: "blocker")
            try Data().write(to: blocker)
            let result = WholesetStore.loadAppContainer(cloudKit: false, url: blocker.appending(path: "Test.store"))
            #expect(result.mode == .inMemory)
            #expect(result.container?.configurations.first?.isStoredInMemoryOnly == true)
        }
    }
}
