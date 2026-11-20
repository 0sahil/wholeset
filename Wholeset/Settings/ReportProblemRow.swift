// SPDX-License-Identifier: GPL-3.0-or-later

import MessageUI
import SwiftUI
import UIKit
import WholesetKit

/// Settings' "Report a Problem" row: opens an email to the developer, prefilled with the app
/// version and the device model, for the user to complete, edit and send (or not).
///
/// It composes in the app when Mail is set up, else hands a `mailto:` link to whichever mail
/// app the user has, else shows the address with a button to copy it. The app itself sends
/// nothing and makes no network connection.
struct ReportProblemRow: View {
    @Environment(\.openURL) private var openURL
    @State private var isComposing = false
    @State private var showsAddress = false

    var body: some View {
        Button {
            report()
        } label: {
            HStack {
                Text("Report a Problem")
                Spacer()
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .listRowButtonLabel()
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens an email to the developer that you can edit before sending.")
        .sheet(isPresented: $isComposing) {
            MailComposer(report: AppInfo.problemReport)
                .ignoresSafeArea()
        }
        .alert("Report a Problem", isPresented: $showsAddress) {
            Button("Copy Address") {
                UIPasteboard.general.string = ProblemReport.recipient
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail app is set up on this iPhone. Email your report to \(ProblemReport.recipient).")
        }
    }

    private func report() {
        if MFMailComposeViewController.canSendMail() {
            isComposing = true
        } else if let url = AppInfo.problemReport.mailtoURL {
            openURL(url) { accepted in
                if !accepted { showsAddress = true }
            }
        } else {
            showsAddress = true
        }
    }
}

/// The system mail composer, prefilled with a ``ProblemReport``; it dismisses itself when
/// the user sends, saves or cancels.
private struct MailComposer: UIViewControllerRepresentable {
    let report: ProblemReport
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([ProblemReport.recipient])
        composer.setSubject(report.subject)
        composer.setMessageBody(report.body, isHTML: false)
        return composer
    }

    func updateUIViewController(_ composer: MFMailComposeViewController, context: Context) {
        context.coordinator.dismiss = dismiss
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        var dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: (any Error)?
        ) {
            dismiss()
        }
    }
}

/// The app's version and build, and the problem report built from them and the device.
enum AppInfo {
    /// The marketing version, for example "1.0.1".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    /// The build number.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    /// A problem report for this app on this iPhone. The paired Watch's details are left
    /// for the user to fill in: reading them would need WatchConnectivity, which the app
    /// does not use.
    static var problemReport: ProblemReport {
        let device = UIDevice.current
        return ProblemReport(
            appVersion: version,
            build: build,
            deviceModel: modelIdentifier,
            systemVersion: "\(device.systemName) \(device.systemVersion)"
        )
    }

    /// The hardware model identifier, for example "iPhone17,1" (the simulated model in
    /// the Simulator).
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
