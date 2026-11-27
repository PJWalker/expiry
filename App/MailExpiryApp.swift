import SwiftUI

@main
struct MailExpiryApp: App {
    @StateObject private var engine = ExpiryEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Mail Expiry", systemImage: "hourglass") {
            Text("\(engine.expiringCount) set to archive")
            if let status = engine.scanStatus { Text(status) }
            if let last = engine.lastRun { Text("Last check: \(last.formatted(date: .omitted, time: .shortened))") }
            if let err = engine.lastError { Text(err) }
            Divider()
            Button("Open Mail Expiry…") { openWindow(id: "main"); NSApp.activate() }
            Button("Check now") { Task { await engine.run() } }.disabled(engine.busy)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Window("Mail Expiry", id: "main") {
            MainView().environmentObject(engine)
        }
        .defaultSize(width: 900, height: 560)
    }
}
