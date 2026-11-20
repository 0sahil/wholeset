// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import WholesetKit

@Suite("Cloud configuration from Info.plist")
struct CloudConfigurationTests {
    private let containerKey = CloudConfiguration.containerIdentifierKey
    private let enabledKey = CloudConfiguration.iCloudEnabledKey

    // MARK: Container identifier

    @Test func readsTheContainerFromInfoPlist() {
        let configuration = CloudConfiguration(infoDictionary: [containerKey: "iCloud.com.example.ws"])
        #expect(configuration.containerIdentifier == "iCloud.com.example.ws")
    }

    @Test func trimsTheContainer() {
        #expect(CloudConfiguration.containerIdentifier(from: "  iCloud.com.example.ws\n") == "iCloud.com.example.ws")
    }

    @Test func missingContainerFallsBackToTheShippedOne() {
        #expect(CloudConfiguration(infoDictionary: [:]).containerIdentifier == "iCloud.app.wholeset")
        #expect(CloudConfiguration(infoDictionary: nil).containerIdentifier == "iCloud.app.wholeset")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func emptyContainerFallsBack(value: String) {
        #expect(CloudConfiguration.containerIdentifier(from: value) == CloudConfiguration.defaultContainerIdentifier)
    }

    @Test(arguments: ["$(WHOLESET_ICLOUD_CONTAINER)", "${WHOLESET_ICLOUD_CONTAINER}", "iCloud.$(BUNDLE_ID_PREFIX)"])
    func unexpandedBuildSettingFallsBack(value: String) {
        #expect(CloudConfiguration.containerIdentifier(from: value) == CloudConfiguration.defaultContainerIdentifier)
    }

    @Test func nonStringContainerFallsBack() {
        #expect(CloudConfiguration.containerIdentifier(from: 42) == CloudConfiguration.defaultContainerIdentifier)
        #expect(CloudConfiguration.containerIdentifier(from: ["iCloud.com.example.ws"]) == CloudConfiguration.defaultContainerIdentifier)
    }

    // MARK: iCloud switch

    @Test(arguments: ["NO", "no", " No ", "false", "FALSE", "0"])
    func explicitOffTurnsICloudOff(value: String) {
        #expect(!CloudConfiguration.isICloudEnabled(from: value))
    }

    @Test(arguments: ["YES", "yes", "true", "1", "", "  ", "$(WHOLESET_ICLOUD)", "maybe"])
    func anythingElseKeepsICloudOn(value: String) {
        #expect(CloudConfiguration.isICloudEnabled(from: value))
    }

    @Test func booleanValuesAreTakenAsIs() {
        #expect(CloudConfiguration.isICloudEnabled(from: true))
        #expect(!CloudConfiguration.isICloudEnabled(from: false))
    }

    @Test func missingSwitchKeepsICloudOn() {
        #expect(CloudConfiguration.isICloudEnabled(from: nil))
        #expect(CloudConfiguration(infoDictionary: [containerKey: "iCloud.com.example.ws"]).isICloudEnabled)
    }

    @Test func readsBothKeysOfABuildWithoutICloud() {
        let configuration = CloudConfiguration(infoDictionary: [containerKey: "iCloud.com.example.ws", enabledKey: "NO"])
        #expect(configuration == CloudConfiguration(containerIdentifier: "iCloud.com.example.ws", isICloudEnabled: false))
    }

    // MARK: Running app

    @Test func packageTestsUseTheShippedDefaults() {
        #expect(CloudConfiguration.main == CloudConfiguration())
        #expect(WholesetStore.cloudKitContainerIdentifier == "iCloud.app.wholeset")
    }
}
