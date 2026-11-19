// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import CoreData
import Foundation
import os
import Synchronization
import SwiftData

/// Creates the complete CloudKit development schema for the current model (Debug builds only).
///
/// SwiftData only adds a CloudKit field once a record with a non-nil value for it is
/// exported, so optional attributes that were never set, and the join records of
/// many-to-many relationships, can be missing from the development schema. This builds a
/// Core Data model from the SwiftData model types and asks `NSPersistentCloudKitContainer`
/// to upload one fully populated representative record per record type, which creates every
/// field; CloudKit then deletes those records again.
///
/// Run it once, on a device signed into iCloud, against the development environment
/// before deploying the schema to production. It never opens the app's store: it works on a
/// throwaway store in a temporary directory that is deleted afterwards.
public enum CloudKitSchemaInitializer {
    /// What a successful run did.
    public struct Report: Sendable, Equatable {
        /// The iCloud container the schema was created in.
        public let containerIdentifier: String
        /// The Core Data entities whose record types were initialized, sorted by name.
        public let entityNames: [String]
    }

    /// Why the schema could not be initialized.
    public enum Failure: Error, LocalizedError, Equatable {
        /// SwiftData could not build a Core Data model from the model types.
        case modelUnavailable

        public var errorDescription: String? {
            switch self {
            case .modelUnavailable: "Could not build a Core Data model from the SwiftData models."
            }
        }
    }

    /// The SwiftData model types the schema is created for: those of ``CurrentSchema``.
    public static var modelTypes: [any PersistentModel.Type] { CurrentSchema.models }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset",
        category: "CloudKitSchema"
    )

    /// Uploads the full development schema of ``modelTypes`` to a CloudKit container.
    ///
    /// Slow and does network work: call it off the main thread. Blocks until CloudKit has
    /// answered.
    ///
    /// - Parameters:
    ///   - containerIdentifier: The iCloud container; defaults to
    ///     ``WholesetStore/cloudKitContainerIdentifier``.
    ///   - directory: Where the temporary store folder is created; defaults to the
    ///     temporary directory. The folder is removed before this returns or throws.
    /// - Returns: The container and the entities that were initialized.
    /// - Throws: ``Failure/modelUnavailable``, or the Core Data or CloudKit error that
    ///   stopped loading the store or creating the schema.
    public static func initializeDevelopmentSchema(
        containerIdentifier: String = WholesetStore.cloudKitContainerIdentifier,
        in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> Report {
        let model = try makeManagedObjectModel()
        logger.notice("Initializing CloudKit schema in \(containerIdentifier, privacy: .public)")
        do {
            try withTemporaryStore(model: model, containerIdentifier: containerIdentifier, in: directory) { container in
                try container.initializeCloudKitSchema(options: [])
            }
        } catch {
            logger.error("CloudKit schema initialization failed: \(error, privacy: .public)")
            throw error
        }
        let report = Report(
            containerIdentifier: containerIdentifier,
            entityNames: model.entities.compactMap(\.name).sorted()
        )
        logger.notice("Initialized CloudKit schema for \(report.entityNames.joined(separator: ", "), privacy: .public)")
        return report
    }

    /// The Core Data model SwiftData derives from ``modelTypes``: the one CloudKit mirroring
    /// sees for the app's store.
    static func makeManagedObjectModel() throws -> NSManagedObjectModel {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            throw Failure.modelUnavailable
        }
        return model
    }

    /// Loads a new SQLite store for `model` in a fresh folder inside `directory`, runs
    /// `body` with its container, then removes the store and deletes the folder, whether or
    /// not loading or `body` failed.
    ///
    /// - Parameter containerIdentifier: Mirror the store to this iCloud container; `nil`
    ///   keeps it local (tests).
    static func withTemporaryStore<Value>(
        model: NSManagedObjectModel,
        containerIdentifier: String?,
        in directory: URL,
        _ body: (NSPersistentCloudKitContainer) throws -> Value
    ) throws -> Value {
        let folder = directory.appending(path: "WholesetCloudKitSchema-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                logger.error("Could not delete temporary schema store: \(error, privacy: .public)")
            }
        }

        let description = NSPersistentStoreDescription(url: folder.appending(path: "Schema.store"))
        description.shouldAddStoreAsynchronously = false
        if let containerIdentifier {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        let container = NSPersistentCloudKitContainer(name: "WholesetCloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        let loadError = Mutex<(any Error)?>(nil)
        container.loadPersistentStores { _, error in
            if let error { loadError.withLock { $0 = error } }
        }

        let coordinator = container.persistentStoreCoordinator
        defer {
            for store in coordinator.persistentStores {
                do {
                    try coordinator.remove(store)
                } catch {
                    logger.error("Could not remove temporary schema store: \(error, privacy: .public)")
                }
            }
        }
        if let error = loadError.withLock({ $0 }) { throw error }
        return try body(container)
    }
}
#endif
