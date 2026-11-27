import SwiftUI

/// Manual handling per sender. Each setting is stored as a From rule at the top of Rules.
struct SendersView: View {
    @EnvironmentObject var engine: ExpiryEngine
    @State private var rules = Store.loadRules()
    @State private var newSender = ""
    @State private var search = ""

    private struct Row: Identifiable {
        var address: String
        var count: Int
        var rule: Rule?
        var id: String { address }
    }

    private var rows: [Row] {
        var counts: [String: Int] = [:]
        for m in engine.messages { counts[m.senderAddress, default: 0] += 1 }
        for r in rules { if let a = r.senderAddress, counts[a] == nil { counts[a] = 0 } }
        return counts.map { a, c in Row(address: a, count: c, rule: rules.first { $0.senderAddress == a }) }
            .filter { search.isEmpty || $0.address.contains(search.lowercased()) }
            .sorted { ($0.rule != nil ? 0 : 1, -$0.count, $0.address) < ($1.rule != nil ? 0 : 1, -$1.count, $1.address) }
    }

    var body: some View {
        Table(rows) {
            TableColumn("Sender") { r in
                VStack(alignment: .leading) {
                    Text(r.address).lineLimit(1)
                    Text(r.count == 1 ? "1 message" : "\(r.count) messages").font(.caption).foregroundStyle(.secondary)
                }
            }
            TableColumn("Handling") { r in
                HStack {
                    Picker("", selection: Binding<Rule.Outcome?>(
                        get: { r.rule?.outcome == .assess && r.rule?.supersede != nil ? nil : r.rule?.outcome },
                        set: { update(r, outcome: $0, days: r.rule?.days ?? 7, supersede: r.rule?.supersede) }
                    )) {
                        Text("Default (Siri / other rules)").tag(Rule.Outcome?.none)
                        ForEach(Rule.Outcome.allCases, id: \.self) { Text($0.label).tag(Rule.Outcome?.some($0)) }
                    }.labelsHidden()
                    if r.rule?.outcome == .afterDays {
                        Stepper("\(r.rule?.days ?? 7)d", value: Binding(
                            get: { r.rule?.days ?? 7 },
                            set: { update(r, outcome: .afterDays, days: $0, supersede: r.rule?.supersede) }
                        ), in: 1...365)
                    }
                }
            }.width(min: 220, ideal: 260)
            TableColumn("Older messages") { r in
                Picker("", selection: Binding<Rule.Supersede?>(
                    get: { r.rule?.supersede },
                    set: { update(r, outcome: currentOutcome(r), days: r.rule?.days ?? 7, supersede: $0) }
                )) {
                    Text("Default (Siri decides)").tag(Rule.Supersede?.none)
                    ForEach(Rule.Supersede.allCases.filter { $0 != .assess }, id: \.self) { Text($0.label).tag(Rule.Supersede?.some($0)) }
                }.labelsHidden()
            }.width(min: 200, ideal: 230)
        }
        .searchable(text: $search, prompt: "Filter senders")
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Add sender address", text: $newSender).onSubmit(add)
                Button("Add", action: add).disabled(!newSender.contains("@"))
                Spacer()
                Text("Sender settings beat broader rules.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.bar)
        }
        .onAppear { rules = Store.loadRules(); engine.reload() }
    }

    /// Outcome to keep when only the older-messages setting changes.
    private func currentOutcome(_ r: Row) -> Rule.Outcome? {
        guard let o = r.rule?.outcome else { return nil }
        return o == .assess && r.rule?.supersede != nil ? nil : o
    }

    private func update(_ r: Row, outcome: Rule.Outcome?, days: Int, supersede: Rule.Supersede?) {
        engine.setSenderRule(r.address, outcome: outcome, days: days, supersede: supersede, rules: &rules)
        Store.saveRules(rules)
    }

    private func add() {
        let a = TrackedMessage.address(newSender)
        guard a.contains("@") else { return }
        engine.setSenderRule(a, outcome: .fleeting, days: 7, supersede: nil, rules: &rules)
        Store.saveRules(rules)
        newSender = ""
    }
}
