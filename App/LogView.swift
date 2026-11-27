import SwiftUI
import AppKit

/// Every decision and action, newest first. Stored as JSON lines in the App Group folder.
struct LogView: View {
    @State private var entries: [LogEntry] = []
    @State private var search = ""
    @AppStorage("logDecisions", store: UserDefaults(suiteName: Config.appGroup)) private var enabled = true

    private var filtered: [LogEntry] {
        guard !search.isEmpty else { return entries }
        let q = search.lowercased()
        return entries.filter {
            [$0.subject, $0.from, $0.event, $0.detail ?? "", $0.category?.label ?? ""].contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        Table(filtered) {
            TableColumn("Time") { Text($0.date.formatted(date: .abbreviated, time: .shortened)) }.width(min: 120, ideal: 140)
            TableColumn("Event", value: \.event).width(min: 70, ideal: 80)
            TableColumn("Message") { e in
                VStack(alignment: .leading) {
                    Text(e.subject).lineLimit(1)
                    Text(e.from).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            TableColumn("Decision") { e in
                VStack(alignment: .leading) {
                    Text(e.category?.label ?? "")
                    if let at = e.archiveAt {
                        Text("Archive \(at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.width(min: 140, ideal: 170)
            TableColumn("By") { Text($0.source?.rawValue ?? "") }.width(50)
            TableColumn("Detail") { Text($0.detail ?? "").lineLimit(2).foregroundStyle(.secondary) }
        }
        .searchable(text: $search, prompt: "Filter log")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(enabled ? "No decisions logged yet" : "Logging is off",
                                       systemImage: "list.bullet.rectangle",
                                       description: Text(enabled ? "Decisions appear here as messages are assessed and archived." : "Turn it on below or in Settings."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Toggle("Log decisions", isOn: $enabled)
                Spacer()
                Button("Refresh") { load() }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.root]) }
                Button("Clear Log", role: .destructive) { DecisionLog.clear(); load() }
            }
            .padding(8)
            .background(.bar)
        }
        .onAppear { load() }
    }

    private func load() { entries = DecisionLog.load() }
}
