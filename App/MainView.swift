import SwiftUI

/// The app's single window: sidebar with Messages, Senders, Rules, Log and Settings.
struct MainView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case messages = "Messages", senders = "Senders", rules = "Rules", log = "Log", settings = "Settings"
        var id: Self { self }
        var icon: String {
            switch self {
            case .messages: "tray"
            case .senders: "person.2"
            case .rules: "line.3.horizontal.decrease.circle"
            case .log: "list.bullet.rectangle"
            case .settings: "gearshape"
            }
        }
    }

    @EnvironmentObject var engine: ExpiryEngine
    @SceneStorage("pane") private var pane: Pane = .messages
    @State private var showRescan = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(get: { pane }, set: { pane = $0 ?? .messages })) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch pane {
                case .messages: MessagesView()
                case .senders: SendersView()
                case .rules: RulesView()
                case .log: LogView()
                case .settings: SettingsPane()
                }
            }
            .navigationTitle(pane.rawValue)
            .toolbar {
                ToolbarItemGroup {
                    if let status = engine.scanStatus {
                        ProgressView().controlSize(.small)
                        Text(status).foregroundStyle(.secondary)
                    }
                    Button { showRescan = true } label: { Label("Rescan Inbox", systemImage: "arrow.clockwise") }
                        .help("Assess messages already in your Inbox")
                        .disabled(engine.busy)
                    Button { Task { await engine.run() } } label: { Label("Check now", systemImage: "hourglass") }
                        .help("Assess new messages and archive overdue ones")
                        .disabled(engine.busy)
                }
            }
        }
        .sheet(isPresented: $showRescan) { RescanSheet() }
        .frame(minWidth: 760, minHeight: 440)
    }
}

private struct RescanSheet: View {
    @EnvironmentObject var engine: ExpiryEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rescanDays") private var days = 30
    @AppStorage("rescanReassess") private var reassess = false

    var body: some View {
        Form {
            Picker("Messages from", selection: $days) {
                Text("Last 7 days").tag(7)
                Text("Last 30 days").tag(30)
                Text("Last 90 days").tag(90)
                Text("Whole Inbox").tag(0)
            }
            Toggle("Re-assess messages already assessed", isOn: $reassess)
            Text("Flagged messages and your manual choices are left alone. Anything already overdue gets 24 hours before it's archived, so you can review it first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Rescan") {
                    dismiss()
                    Task { await engine.rescan(days: days, reassess: reassess) }
                }
            }
        }
    }
}
