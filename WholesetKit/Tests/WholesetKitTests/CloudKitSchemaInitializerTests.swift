// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import CoreData
import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// The Core Data model the CloudKit development schema is created from must cover every
/// stored property of the current SwiftData schema, or the production schema would lack
/// fields. Nothing here talks to CloudKit.
@Suite("CloudKit schema initializer")
struct CloudKitSchemaInitializerTests {
    private let schema = Schema(versionedSchema: CurrentSchema.self)

    private func model() throws -> NSManagedObjectModel {
        try CloudKitSchemaInitializer.makeManagedObjectModel()
    }

    @Test func usesTheCurrentSchemaModels() {
        let names = CloudKitSchemaInitializer.modelTypes.map { String(describing: $0) }
        #expect(names == CurrentSchema.models.map { String(describing: $0) })
        #expect(names.count == schema.entities.count)
    }

    @Test func containsEveryEntity() throws {
        let model = try model()
        #expect(Set(model.entities.compactMap(\.name)) == Set(schema.entities.map(\.name)))
        #expect(model.entities.count == schema.entities.count)
    }

    @Test func containsEveryStoredAttribute() throws {
        let entities = try model().entitiesByName
        for entity in schema.entities {
            let described = try #require(entities[entity.name], "\(entity.name) is missing")
            #expect(!entity.attributes.isEmpty)
            for attribute in entity.attributes {
                let label = "\(entity.name).\(attribute.name)"
                let match = try #require(described.attributesByName[attribute.name], "\(label) is missing")
                #expect(match.isOptional == attribute.isOptional, "\(label) optionality differs")
                #expect(match.isOptional || match.defaultValue != nil, "\(label) is neither optional nor defaulted")
            }
        }
    }

    @Test func containsEveryRelationshipWithItsInverse() throws {
        let entities = try model().entitiesByName
        for entity in schema.entities {
            let described = try #require(entities[entity.name], "\(entity.name) is missing")
            #expect(Set(described.relationshipsByName.keys) == Set(entity.relationships.map(\.name)), "\(entity.name)")
            for relationship in entity.relationships {
                let label = "\(entity.name).\(relationship.name)"
                let match = try #require(described.relationshipsByName[relationship.name], "\(label) is missing")
                #expect(match.destinationEntity?.name == relationship.destination, "\(label) destination")
                #expect(match.isToMany == !relationship.isToOneRelationship, "\(label) cardinality")
                #expect(match.isOptional, "\(label) is not optional")
                #expect(match.inverseRelationship?.name == relationship.inverseName, "\(label) inverse")
            }
        }
    }

    /// The fields that were missing from the development schema because no exported record
    /// had a value for them.
    @Test(arguments: [
        ("Exercise", "progressionStepKg", NSAttributeType.doubleAttributeType),
        ("Exercise", "defaultRestSeconds", .integer64AttributeType),
        ("Session", "externalKey", .stringAttributeType),
        ("SetLog", "durationSeconds", .integer64AttributeType),
        ("SetLog", "rpe", .doubleAttributeType),
    ])
    func containsRarelySetOptionalAttributes(entity: String, attribute: String, type: NSAttributeType) throws {
        let described = try #require(try model().entitiesByName[entity])
        let match = try #require(described.attributesByName[attribute], "\(entity).\(attribute) is missing")
        #expect(match.isOptional)
        #expect(match.attributeType == type, "\(entity).\(attribute) is \(match.attributeType.rawValue)")
    }

    /// `Exercise.alternatives` and `alternativeOf` form the many-to-many relationship
    /// CloudKit mirroring stores as separate join records.
    @Test func containsManyToManyAlternatives() throws {
        let exercise = try #require(try model().entitiesByName["Exercise"])
        let alternatives = try #require(exercise.relationshipsByName["alternatives"])
        let alternativeOf = try #require(exercise.relationshipsByName["alternativeOf"])
        #expect(alternatives.isToMany && alternativeOf.isToMany)
        #expect(alternatives.destinationEntity?.name == "Exercise")
        #expect(alternativeOf.destinationEntity?.name == "Exercise")
        #expect(alternatives.inverseRelationship === alternativeOf)
        #expect(alternativeOf.inverseRelationship === alternatives)
        #expect(alternatives.deleteRule == .nullifyDeleteRule)
    }

    @Test func temporaryStoreLoadsAndIsDeletedAfterwards() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSchemaInitializerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = try CloudKitSchemaInitializer.withTemporaryStore(
            model: try model(),
            containerIdentifier: nil,
            in: directory
        ) { container in
            let store = try #require(container.persistentStoreCoordinator.persistentStores.first)
            let url = try #require(store.url)
            #expect(url.path(percentEncoded: false).hasPrefix(directory.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            #expect(store.type == NSSQLiteStoreType)
            return url
        }

        #expect(!FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(leftovers.isEmpty)
    }

    @Test func temporaryStoreIsDeletedWhenTheBodyThrows() throws {
        struct Expected: Error {}
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSchemaInitializerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: Expected.self) {
            try CloudKitSchemaInitializer.withTemporaryStore(model: try model(), containerIdentifier: nil, in: directory) { _ in
                throw Expected()
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty)
    }

    @Test func defaultsToTheAppContainer() {
        #expect(WholesetStore.cloudKitContainerIdentifier == "iCloud.app.wholeset")
    }
}
#endif
