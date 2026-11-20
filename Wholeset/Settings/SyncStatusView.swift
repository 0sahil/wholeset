// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// iCloud sync in detail: the account, how the store is opened, and the last import and
/// export seen since the app was opened.
struct SyncStatusView: View {
    let sync: SyncMonitor

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: SyncStatusText.summary(sync.status))
                if let detail = SyncStatusText.detail(sync.status) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("iCloud Account", value: SyncStatusText.account(sync.account, mode: sync.mode))
                LabeledContent("Data", value: SyncStatusText.mode(sync.mode))
            }
            // A build without iCloud never syncs, so there is no activity to show.
            if sync.status != .offInThisBuild {
                Section {
                    LabeledContent("Last Download", value: SyncStatusText.event(sync.activity.lastImport))
                    LabeledContent("Last Upload", value: SyncStatusText.event(sync.activity.lastExport))
                } footer: {
                    Text("Shows sync activity since Wholeset was opened. Changes reach your other devices when iCloud delivers them, which can take a few minutes, especially on Apple Watch.")
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            sync.refreshAccountStatus()
        }
    }
}

/// Wording for sync states.
enum SyncStatusText {
    /// One line for the Settings row.
    static func summary(_ status: SyncStatus) -> String {
        switch status {
        case .off(.inMemory): String(localized: "Off (temporary data)")
        case .off: String(localized: "Off on this device")
        case .offInThisBuild: String(localized: "Off in this build")
        case .checkingAccount: String(localized: "Checking…")
        case .accountUnavailable(.noAccount): String(localized: "Not signed in to iCloud")
        case .accountUnavailable(.restricted): String(localized: "iCloud is restricted")
        case .accountUnavailable(.temporarilyUnavailable): String(localized: "iCloud needs attention")
        case .accountUnavailable: String(localized: "iCloud unavailable")
        case .syncing: String(localized: "Syncing…")
        case .failed: String(localized: "Last sync failed")
        case .upToDate(let date): String(localized: "Up to date · \(date.formatted(.relative(presentation: .named)))")
        case .waiting: String(localized: "Waiting for iCloud")
        }
    }

    /// An explanation for states that need one.
    static func detail(_ status: SyncStatus) -> String? {
        switch status {
        case .off(.inMemory):
            String(localized: "Wholeset couldn't open its database, so changes are kept only until the app quits.")
        case .off:
            String(localized: "This build keeps data on this device only. Builds installed on a device with iCloud sync data through your iCloud account.")
        case .offInThisBuild:
            String(localized: "iCloud sync is off in this build of Wholeset. Your routines and workouts stay on this device and aren't shared with your other devices.")
        case .accountUnavailable(.noAccount):
            String(localized: "Sign in to iCloud in Settings to sync routines and workouts between iPhone and Apple Watch.")
        case .accountUnavailable(.temporarilyUnavailable):
            String(localized: "Your iCloud account needs attention in Settings before sync can continue.")
        case .accountUnavailable:
            String(localized: "Sync resumes when iCloud is available again. Your data stays on this device meanwhile.")
        case .failed(_, let message):
            message.isEmpty ? nil : message
        case .waiting:
            String(localized: "No sync activity yet since Wholeset was opened.")
        case .checkingAccount, .syncing, .upToDate:
            nil
        }
    }

    static func account(_ account: CloudAccountStatus?, mode: WholesetStore.Mode) -> String {
        guard mode == .cloudKit else { return String(localized: "Not used") }
        switch account {
        case nil: return String(localized: "Checking…")
        case .available: return String(localized: "Signed in")
        case .noAccount: return String(localized: "Not signed in")
        case .restricted: return String(localized: "Restricted")
        case .temporarilyUnavailable: return String(localized: "Needs attention")
        case .couldNotDetermine: return String(localized: "Unknown")
        }
    }

    static func mode(_ mode: WholesetStore.Mode) -> String {
        switch mode {
        case .cloudKit: String(localized: "Synced with iCloud")
        case .local: String(localized: "On this device only")
        case .inMemory: String(localized: "Temporary")
        }
    }

    static func event(_ event: SyncEvent?) -> String {
        guard let event, let end = event.endDate else { return String(localized: "None yet") }
        let time = end.formatted(date: .omitted, time: .shortened)
        return event.succeeded ? time : String(localized: "Failed at \(time)")
    }
}
