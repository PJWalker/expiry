import SwiftUI

/// Manual overrides. The first matching rule wins; anything unmatched is assessed by the Siri model.
struct RulesView: View {
    @State private var rules = Store.loadRules()

    var body: some View {
        Form {
            Section {
                ForEach($rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                        Picker("", selection: $rule.field) {
                            ForEach(Rule.Field.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                        }.labelsHidden().frame(width: 90)
                        Picker("", selection: $rule.op) {
                            ForEach(Rule.Op.allCases, id: \.self) { Text($0.rawValue) }
                        }.labelsHidden().frame(width: 100)
                        TextField("value", text: $rule.value)
                        Picker("", selection: $rule.outcome) {
                            ForEach(Rule.Outcome.allCases, id: \.self) { Text($0.label) }
                        }.labelsHidden().frame(width: 180)
                        if rule.outcome == .afterDays {
                            Stepper("\(rule.days)d", value: $rule.days, in: 1...365).frame(width: 70)
                        }
                        Button(role: .destructive) { rules.removeAll { $0.id == rule.id } } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
                Button("Add rule") { rules.append(Rule()) }
            } header: {
                Text("Overrides")
            } footer: {
                Text("First matching rule wins. Everything else is assessed by the on-device Siri model.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: rules) { _, new in Store.saveRules(new) }
    }
}
