import SwiftUI

struct RulesView: View {
    @State private var rules = Store.loadRules()
    @AppStorage("archiveMailbox", store: UserDefaults(suiteName: Config.appGroup))
    private var archiveMailbox = "Archive"

    var body: some View {
        Form {
            Section("Messages matching any rule expire after 24 hours") {
                ForEach($rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                        Picker("", selection: $rule.field) {
                            ForEach(Rule.Field.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                        }.labelsHidden().frame(width: 100)
                        Picker("", selection: $rule.op) {
                            ForEach(Rule.Op.allCases, id: \.self) { Text($0.rawValue) }
                        }.labelsHidden().frame(width: 110)
                        TextField("value", text: $rule.value)
                        Button(role: .destructive) { rules.removeAll { $0.id == rule.id } } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                Button("Add rule") { rules.append(Rule()) }
            }
            Section("Archive") {
                TextField("Archive mailbox name", text: $archiveMailbox)
                Text("Gmail: use [Gmail]/All Mail").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 400)
        .onChange(of: rules) { Store.saveRules($0) }
    }
}
