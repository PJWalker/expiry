import SwiftUI

/// Recent messages with their assessment and archive date. Each can be overridden.
struct MessagesView: View {
    @EnvironmentObject var engine: ExpiryEngine

    var body: some View {
        List(engine.messages) { m in
            MessageRow(message: m)
        }
        .overlay {
            if engine.messages.isEmpty {
                ContentUnavailableView("No messages yet", systemImage: "tray",
                                       description: Text("New Inbox messages appear here once the Mail extension is enabled. Use Rescan Inbox to assess messages already there."))
            }
        }
        .onAppear { engine.reload() }
    }
}

private struct MessageRow: View {
    @EnvironmentObject var engine: ExpiryEngine
    let message: TrackedMessage

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.subject).fontWeight(.medium).lineLimit(1)
                Text(message.from).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(.secondary)
                if let reason = message.reason {
                    Text(reason).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { message.category },
                set: { new in engine.override(message.id, category: new, until: new == .dated ? defaultDate : nil) }
            )) {
                ForEach(Category.allCases.filter { $0 != .unassessed }, id: \.self) { Text($0.label).tag($0) }
                if message.category == .unassessed { Text(Category.unassessed.label).tag(Category.unassessed) }
            }
            .labelsHidden().frame(width: 190)
            if message.category == .dated {
                DatePicker("", selection: Binding(
                    get: { defaultDate },
                    set: { engine.override(message.id, category: .dated, until: $0) }
                ), displayedComponents: .date)
                .labelsHidden()
            }
            Menu {
                Button("Always do this for this sender") { engine.addSenderRule(for: message) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 30)
        }
    }

    /// Last relevant day: the model's date, or a week after receipt.
    private var defaultDate: Date {
        message.relevantUntil ?? message.received.addingTimeInterval(7 * 86_400)
    }

    private var status: String {
        let by = switch message.source { case .model: "Siri model"; case .rule: "rule"; case .user: "you" }
        guard message.category != .unassessed else { return "Waiting for assessment" }
        guard let at = message.archiveAt else { return "Stays in Inbox · set by \(by)" }
        return "Archives \(at.formatted(date: .abbreviated, time: .shortened)) · set by \(by)"
    }
}
