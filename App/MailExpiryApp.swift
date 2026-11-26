import SwiftUI

@main
struct MailExpiryApp: App {
    @StateObject private var engine = ExpiryEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Mail Expiry", systemImage: "hourglass") {
            Text("\(engine.expiringCount) set to archive")
            if let last = engine.lastRun { Text("Last check: \(last.formatted(date: .omitted, time: .shortened))") }
            if let err = engine.lastError { Text(err) }
            Divider()
            Button("Messages…") { openWindow(id: "messages"); NSApp.activate() }
            SettingsLink { Text("Rules…") }
            Button("Check now") { Task { await engine.run() } }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Window("Mail Expiry", id: "messages") {
            MessagesView().environmentObject(engine)
        }
        Settings { RulesView() }
    }
}
