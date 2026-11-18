// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData
import Testing
@testable import WholesetKit

/// Checks every schema version against the rules CloudKit mirroring imposes, as far as
/// SwiftData's `Schema` API exposes them.
@Suite("Schema follows CloudKit rules")
struct SchemaConformanceTests {
    static let versions: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self]

    private func schema(_ version: any VersionedSchema.Type) -> Schema {
        Schema(versionedSchema: version)
    }

    @Test(arguments: versions.indices)
    func containsEveryModel(_ index: Int) {
        #expect(Set(schema(Self.versions[index]).entities.map(\.name)) == [
            "Exercise", "Routine", "RoutineItem", "WeekPlanDay",
            "Session", "SessionExercise", "SetLog", "AppSettings",
        ])
    }

    @Test func versionsAndMigrationPlan() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(WholesetMigrationPlan.schemas.map { $0.versionIdentifier } == [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)])
        #expect(WholesetMigrationPlan.stages.count == 1)
        #expect(CurrentSchema.versionIdentifier == SchemaV2.versionIdentifier)
        #expect(WholesetStore.schema.entities.count == 8)
    }

    @Test(arguments: versions.indices)
    func noUniqueAttributesOrConstraints(_ index: Int) {
        for entity in schema(Self.versions[index]).entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has uniqueness constraints")
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
            }
            for relationship in entity.relationships {
                #expect(!relationship.isUnique, "\(entity.name).\(relationship.name) is unique")
            }
        }
    }

    @Test(arguments: versions.indices)
    func attributesAreOptionalOrDefaulted(_ index: Int) {
        for entity in schema(Self.versions[index]).entities {
            for attribute in entity.attributes {
                #expect(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) is neither optional nor defaulted"
                )
            }
        }
    }

    @Test(arguments: versions.indices)
    func relationshipsAreOptionalWithMatchingInverse(_ index: Int) throws {
        let schema = schema(Self.versions[index])
        let entitiesByName = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.name, $0) })
        for entity in schema.entities {
            for relationship in entity.relationships {
                let label = "\(entity.name).\(relationship.name)"
                #expect(relationship.isOptional, "\(label) is not optional")

                let inverseName = try #require(relationship.inverseName, "\(label) has no inverse")
                let destination = try #require(entitiesByName[relationship.destination], "\(label) has unknown destination")
                let inverse = try #require(
                    destination.relationships.first { $0.name == inverseName },
                    "\(label) inverse \(inverseName) not found on \(destination.name)"
                )
                #expect(inverse.inverseName == relationship.name, "\(label) inverse does not point back")
                #expect(inverse.destination == entity.name, "\(label) inverse has wrong destination")
            }
        }
    }

    @Test(arguments: versions.indices)
    func deleteRulesMatchOwnership(_ index: Int) throws {
        let cascading: Set<String> = ["Routine.items", "Session.entries", "SessionExercise.sets"]
        for entity in schema(Self.versions[index]).entities {
            for relationship in entity.relationships {
                let label = "\(entity.name).\(relationship.name)"
                #expect(relationship.deleteRule != .deny, "\(label) uses .deny")
                let expected: Schema.Relationship.DeleteRule = cascading.contains(label) ? .cascade : .nullify
                #expect(relationship.deleteRule == expected, "\(label) is \(relationship.deleteRule)")
            }
        }
    }

    /// Guards the checks above against passing vacuously: the introspection must
    /// report non-optional defaulted attributes and to-many relationships as such.
    @Test func introspectionReportsKnownShapes() throws {
        let schema = schema(SchemaV2.self)
        let exercise = try #require(schema.entities.first { $0.name == "Exercise" })
        let name = try #require(exercise.attributes.first { $0.name == "name" })
        #expect(!name.isOptional)
        #expect(name.defaultValue as? String == "")
        let step = try #require(exercise.attributes.first { $0.name == "progressionStepKg" })
        #expect(step.isOptional)

        let routine = try #require(schema.entities.first { $0.name == "Routine" })
        let items = try #require(routine.relationships.first { $0.name == "items" })
        #expect(!items.isToOneRelationship)
        #expect(items.destination == "RoutineItem")

        let item = try #require(schema.entities.first { $0.name == "RoutineItem" })
        let owner = try #require(item.relationships.first { $0.name == "routine" })
        #expect(owner.isToOneRelationship)
        let targetSets = try #require(item.attributes.first { $0.name == "targetSets" })
        #expect(targetSets.defaultValue as? Int == 3)
    }

    @Test(arguments: versions.indices)
    func everyModelHasIdentityAndTimestamps(_ index: Int) {
        for entity in schema(Self.versions[index]).entities {
            let attributes = Dictionary(uniqueKeysWithValues: entity.attributes.map { ($0.name, $0) })
            #expect(attributes["id"]?.valueType == UUID.self, "\(entity.name).id")
            #expect(attributes["createdAt"]?.valueType == Date.self, "\(entity.name).createdAt")
            #expect(attributes["updatedAt"]?.valueType == Date.self, "\(entity.name).updatedAt")
        }
    }

    @Test func enumsAreStoredAsStrings() {
        let schema = schema(SchemaV2.self)
        let rawAttributes = [
            ("Exercise", "equipmentRaw"), ("Exercise", "primaryMuscleRaw"),
            ("Session", "sourceRaw"), ("AppSettings", "unitRaw"),
            ("AppSettings", "weightCrownSensitivityRaw"), ("AppSettings", "repsCrownSensitivityRaw"),
        ]
        for (entityName, attributeName) in rawAttributes {
            let attribute = schema.entities
                .first { $0.name == entityName }?
                .attributes.first { $0.name == attributeName }
            #expect(attribute?.valueType == String.self, "\(entityName).\(attributeName)")
        }
    }

    /// Version 2 only adds attributes, all optional or defaulted, so the lightweight stage
    /// applies and the CloudKit schema stays additive.
    @Test func versionTwoOnlyAddsOptionalOrDefaultedAttributes() throws {
        let old = schema(SchemaV1.self)
        let new = schema(SchemaV2.self)
        var added: Set<String> = []
        for entity in new.entities {
            let previous = try #require(old.entities.first { $0.name == entity.name })
            let previousAttributes = Set(previous.attributes.map(\.name))
            #expect(Set(entity.relationships.map(\.name)) == Set(previous.relationships.map(\.name)), "\(entity.name) relationships changed")
            #expect(previousAttributes.isSubset(of: Set(entity.attributes.map(\.name))), "\(entity.name) lost an attribute")
            for attribute in entity.attributes where !previousAttributes.contains(attribute.name) {
                added.insert("\(entity.name).\(attribute.name)")
                #expect(attribute.isOptional || attribute.defaultValue != nil)
            }
        }
        #expect(added == [
            "Exercise.libraryKey", "Routine.seedKey",
            "AppSettings.weightCrownSensitivityRaw", "AppSettings.repsCrownSensitivityRaw",
            "AppSettings.starterRoutinesDecidedAt",
        ])
    }
}
