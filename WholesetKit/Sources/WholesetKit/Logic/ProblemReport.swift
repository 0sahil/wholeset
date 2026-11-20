// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The email a user can send to report a problem: recipient, subject and a prefilled body
/// with the app and device details. Building it sends nothing; the user sees and can edit
/// everything in their mail app before choosing to send it.
///
/// The text is in English whatever the device language, because it is written for the
/// developer to read; the user adds their own words in any language.
public struct ProblemReport: Sendable, Equatable {
    /// Where problem reports go.
    public static let recipient = "0sahil.dev@gmail.com"

    /// The app's marketing version, for example "1.0.1".
    public let appVersion: String
    /// The app's build number, for example "202611201530".
    public let build: String
    /// The device's model identifier, for example "iPhone17,1".
    public let deviceModel: String
    /// The operating system's name and version, for example "iOS 26.1".
    public let systemVersion: String
    /// The paired Apple Watch's model and watchOS version, when the app can know them;
    /// `nil` leaves a line for the user to fill in.
    public let watch: String?

    /// Creates a report. Blank values are shown as "unknown".
    public init(appVersion: String, build: String, deviceModel: String, systemVersion: String, watch: String? = nil) {
        self.appVersion = Self.orUnknown(appVersion)
        self.build = Self.orUnknown(build)
        self.deviceModel = Self.orUnknown(deviceModel)
        self.systemVersion = Self.orUnknown(systemVersion)
        let watch = watch?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.watch = watch?.isEmpty == false ? watch : nil
    }

    /// The email's subject, for example "Wholeset 1.0.1 (42): problem report".
    public var subject: String {
        "Wholeset \(appVersion) (\(build)): problem report"
    }

    /// The email's body: empty lines for what happened and how to reproduce it, then the
    /// app and device details. Lines end with "\n".
    public var body: String {
        [
            "What happened:",
            "",
            "",
            "Steps to reproduce:",
            "",
            "",
            "--",
            "App: Wholeset \(appVersion) (\(build))",
            "iPhone: \(deviceModel), \(systemVersion)",
            "Apple Watch: \(watch ?? "(model and watchOS version, if the problem was on the Watch)")",
            "",
        ].joined(separator: "\n")
    }

    /// A `mailto:` URL with the same recipient, subject and body (RFC 6068), for when the
    /// device has no mail account the app can compose in. Line breaks are encoded as CRLF.
    public var mailtoURL: URL? {
        let query = [
            "subject=\(Self.percentEncoded(subject))",
            "body=\(Self.percentEncoded(body.replacingOccurrences(of: "\n", with: "\r\n")))",
        ].joined(separator: "&")
        return URL(string: "mailto:\(Self.recipient)?\(query)")
    }

    /// `text` with everything but RFC 3986's unreserved characters percent-encoded, so no
    /// character of it can be read as a URL delimiter (`&`, `=`, `+`, `#`, `?`).
    private static func percentEncoded(_ text: String) -> String {
        var unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        unreserved.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static func orUnknown(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
