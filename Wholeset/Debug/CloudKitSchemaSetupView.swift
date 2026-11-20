// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import os
import SwiftUI
import WholesetKit

/// Creates the CloudKit development schema instead of showing the app (Debug builds only).
///
/// Launch with `-WholesetInitCloudKitSchema` on a device signed into iCloud. The app then
/// does not open its store; it runs ``CloudKitSchemaInitializer`` once, shows the outcome
/// and logs it with the prefix `WholesetInitCloudKitSchema:`. Nothing of this is compiled
/// into Release builds.
struct CloudKitSchemaSetupView: View {
    /// The launch argument that selects this mode.
    static let launchArgument = "-WholesetInitCloudKitSchema"

    /// Whether the app was launched to initialize the CloudKit schema.
    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    private enum Status {
        case running
        case succeeded(CloudKitSchemaInitializer.Report)
        case failed(String)
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "CloudKitSchema")

    @State private var status = Status.running
    @State private var started = false

    var body: some View {
        VStack(spacing: 16) {
            switch status {
            case .running:
                ProgressView()
                Text(verbatim: "Initializing CloudKit schema…")
                    .font(.headline)
            case .succeeded(let report):
                Image(systemName: "checkmark.icloud")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(verbatim: "CloudKit schema initialized")
                    .font(.headline)
                Text(verbatim: "\(report.containerIdentifier): \(report.entityNames.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.icloud")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(verbatim: "CloudKit schema initialization failed")
                    .font(.headline)
                Text(verbatim: message)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
    }

    private func run() async {
        guard !started else { return }
        started = true
        guard CloudConfiguration.main.isICloudEnabled else {
            Self.logger.error("WholesetInitCloudKitSchema: failed: iCloud is off in this build")
            status = .failed("iCloud is off in this build (WHOLESET_ICLOUD = NO).")
            return
        }
        Self.logger.notice("WholesetInitCloudKitSchema: started")
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try CloudKitSchemaInitializer.initializeDevelopmentSchema()
            }.value
            Self.logger.notice(
                "WholesetInitCloudKitSchema: succeeded for \(report.containerIdentifier, privacy: .public): \(report.entityNames.joined(separator: ", "), privacy: .public)"
            )
            status = .succeeded(report)
        } catch {
            Self.logger.error("WholesetInitCloudKitSchema: failed: \(error, privacy: .public)")
            status = .failed(String(describing: error))
        }
    }
}
#endif
