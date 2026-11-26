import SwiftUI

@main
struct MailExpiryApp: App {
    @StateObject private var engine = ExpiryEngine()

    var body: some Scene {
        MenuBarExtra("Mail Expiry", systemImage: "hourglass") {
            Text("\(engine.pendingCount) expiring")
            if let last = engine.lastRun { Text("Last check: \(last.formatted(date: .omitted, time: .shortened))") }
            if let err = engine.lastError { Text(err).foregroundStyle(.red) }
            Divider()
            Button("Check now") { engine.run() }
            SettingsLink { Text("Rules…") }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { RulesView() }
    }
}
