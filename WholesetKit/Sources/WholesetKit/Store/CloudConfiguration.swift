// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How a build of the app uses iCloud: the CloudKit container it syncs through, and whether
/// it uses iCloud at all.
///
/// Both values come from the app's Info.plist. The build fills them in from the
/// `WHOLESET_ICLOUD_CONTAINER` and `WHOLESET_ICLOUD` build settings (see
/// `Config/Base.xcconfig`), so a build with its own bundle ID prefix, or one made without
/// iCloud, needs no code change. Where the keys are missing (package tests, previews) or
/// hold no usable value, the defaults are those of the shipped app: the
/// ``defaultContainerIdentifier`` container, with iCloud on.
public struct CloudConfiguration: Sendable, Equatable {
    /// Info.plist key holding the CloudKit container identifier.
    public static let containerIdentifierKey = "WholesetCloudKitContainer"
    /// Info.plist key holding `YES` or `NO`: whether the build has the iCloud entitlements.
    public static let iCloudEnabledKey = "WholesetICloudEnabled"
    /// The shipped app's container, used when the Info.plist names none.
    public static let defaultContainerIdentifier = "iCloud.app.wholeset"

    /// The CloudKit container both apps sync through (private database).
    public let containerIdentifier: String
    /// Whether this build was made with iCloud. When `false` the app has no iCloud
    /// entitlement and must not touch CloudKit.
    public let isICloudEnabled: Bool

    /// Creates a configuration from explicit values.
    public init(containerIdentifier: String = Self.defaultContainerIdentifier, isICloudEnabled: Bool = true) {
        self.containerIdentifier = containerIdentifier
        self.isICloudEnabled = isICloudEnabled
    }

    /// Reads the configuration from an Info.plist dictionary, falling back to the defaults
    /// for each value that is missing or unusable.
    ///
    /// - Parameter infoDictionary: Typically `Bundle.main.infoDictionary`.
    public init(infoDictionary: [String: Any]?) {
        self.init(
            containerIdentifier: Self.containerIdentifier(from: infoDictionary?[Self.containerIdentifierKey]),
            isICloudEnabled: Self.isICloudEnabled(from: infoDictionary?[Self.iCloudEnabledKey])
        )
    }

    /// The configuration of the running app, read once from the main bundle.
    public static let main = CloudConfiguration(infoDictionary: Bundle.main.infoDictionary)

    /// The container identifier in an Info.plist value: the trimmed string, or
    /// ``defaultContainerIdentifier`` when the value is missing, not a string, empty, or a
    /// build setting reference that was never expanded (`$(…)` or `${…}`).
    static func containerIdentifier(from value: Any?) -> String {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !isUnexpandedBuildSetting(string) else {
            return defaultContainerIdentifier
        }
        return string
    }

    /// Whether an Info.plist value turns iCloud on. Only an explicit off (`NO`, `false`
    /// or `0`, in any case, or a Boolean `false`) turns it off; anything else, including a
    /// missing or unexpanded value, keeps the shipped default of on.
    static func isICloudEnabled(from value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
        return !["no", "false", "0"].contains(string.lowercased())
    }

    private static func isUnexpandedBuildSetting(_ string: String) -> Bool {
        string.contains("$(") || string.contains("${")
    }
}
