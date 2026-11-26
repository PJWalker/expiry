import AppKit

/// Every 15 min: for each expiring message past its 24h deadline, ask Mail whether it
/// was handled. Handled = no longer in an Inbox (archived/moved/deleted) or flagged.
/// Otherwise move it to the account's archive mailbox. Never deletes.
@MainActor
final class ExpiryEngine: ObservableObject {
    @Published var pendingCount = 0
    @Published var lastRun: Date?
    @Published var lastError: String?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.run() }
        }
        run()
    }

    func run() {
        let pending = Store.loadPending()
        pendingCount = pending.count
        lastRun = Date()
        // Don't launch Mail just to check; wait until the user has it open.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first != nil else { return }

        for p in pending where p.deadline <= Date() {
            switch MailBridge.expire(messageID: p.messageID, archiveMailbox: Config.archiveMailboxName) {
            case .success(let outcome):
                if outcome != .keep { Store.removePending(p.messageID) }
            case .failure(let err):
                lastError = err.localizedDescription
            }
        }
        pendingCount = Store.loadPending().count
    }
}
