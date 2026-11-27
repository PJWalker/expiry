import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject var engine: ExpiryEngine
    @AppStorage("archiveMailbox", store: UserDefaults(suiteName: Config.appGroup)) private var archiveMailbox = "Archive"
    @AppStorage("logDecisions", store: UserDefaults(suiteName: Config.appGroup)) private var logDecisions = true

    var body: some View {
        Form {
            Section("Archive") {
                TextField("Archive mailbox name", text: $archiveMailbox)
                Text("Used in each account. Gmail: [Gmail]/All Mail").font(.caption).foregroundStyle(.secondary)
            }
            Section("Decision log") {
                Toggle("Log every decision and action", isOn: $logDecisions)
            }
            Section("Status") {
                LabeledContent("Siri model", value: Classifier.unavailableReason ?? "Available")
                LabeledContent("Mail", value: ExpiryEngine.mailIsRunning ? "Running" : "Not running (checks wait for Mail)")
                LabeledContent("Set to archive", value: "\(engine.expiringCount)")
                if let last = engine.lastRun {
                    LabeledContent("Last check", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let err = engine.lastError {
                    LabeledContent("Last error") { Text(err).foregroundStyle(.red) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
