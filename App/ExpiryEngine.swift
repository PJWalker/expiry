import AppKit

/// Every 15 min:
/// 1. Assess new messages with the on-device model.
/// 2. Color them in Mail (orange = fleeting, yellow = until a date).
/// 3. For messages past their archive date: if no longer in the Inbox or flagged, they were
///    handled; otherwise move them to the account's archive mailbox. Never deletes.
@MainActor
final class ExpiryEngine: ObservableObject {
    @Published var messages: [TrackedMessage] = []
    @Published var lastRun: Date?
    @Published var lastError: String?
    private var timer: Timer?
    private var running = false

    var expiringCount: Int { messages.filter { $0.archiveAt != nil }.count }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.run() }
        }
        Task { await run() }
    }

    func reload() {
        messages = Store.loadAll().sorted { $0.received > $1.received }
    }

    /// Manual override from the Messages window.
    func override(_ id: String, category: Category, until: Date? = nil) {
        guard var m = Store.loadAll().first(where: { $0.messageID == id }) else { return }
        m.set(category, source: .user, relevantUntil: until)
        Store.save(m)
        reload()
        Task { await applyColors() }
    }

    /// "Always do this for this sender": adds a rule at the top.
    func addSenderRule(for m: TrackedMessage) {
        var rules = Store.loadRules()
        let outcome: Rule.Outcome = switch m.category {
        case .fleeting: .fleeting
        case .needsAttention, .unassessed: .keep
        case .dated: .assess   // dates differ per message, so keep asking the model
        }
        rules.insert(Rule(field: .from, op: .contains, value: Self.address(m.from), outcome: outcome), at: 0)
        Store.saveRules(rules)
    }

    func run() async {
        guard !running else { return }
        running = true
        defer { running = false; lastRun = Date(); reload() }
        lastError = nil

        await assessNew()
        forgetOldKept()

        // Don't launch Mail just to check; wait until the user has it open.
        guard Self.mailIsRunning else { return }
        await applyColors()

        for m in Store.loadAll() {
            guard let due = m.archiveAt, due <= Date() else { continue }
            switch MailBridge.expire(messageID: m.messageID, archiveMailbox: Config.archiveMailboxName) {
            case .success: Store.remove(m.messageID)   // archived, handled or gone
            case .failure(let err): lastError = err.localizedDescription
            }
        }
    }

    private func assessNew() async {
        let pending = Store.loadAll().filter { $0.category == .unassessed }
        guard !pending.isEmpty else { return }
        guard Classifier.isAvailable else {
            lastError = Classifier.unavailableReason
            return
        }
        for var m in pending {
            do {
                let (category, date) = try await Classifier.assess(m)
                // Re-read in case the user overrode it while the model was running.
                guard Store.loadAll().first(where: { $0.messageID == m.messageID })?.category == .unassessed else { continue }
                m.set(category, source: .model, relevantUntil: date)
                // A date already in the past (or unparseable) shouldn't archive instantly.
                if category == .dated, let at = m.archiveAt, at < m.received.addingTimeInterval(Config.fleetingInterval) {
                    m.set(.fleeting, source: .model)
                }
                Store.save(m)
            } catch {
                lastError = "Assessment failed: \(error.localizedDescription)"
            }
        }
    }

    private func applyColors() async {
        guard Self.mailIsRunning else { return }
        for var m in Store.loadAll() where !m.colored && m.category != .unassessed {
            let color = switch m.category {
            case .fleeting: "orange"
            case .dated: "yellow"
            default: "none"
            }
            if case .success = MailBridge.setColor(messageID: m.messageID, color: color) {
                m.colored = true
                Store.save(m)
            }
        }
    }

    private func forgetOldKept() {
        for m in Store.loadAll() where m.archiveAt == nil && m.category != .unassessed
            && m.received < Date().addingTimeInterval(-Config.forgetKeptAfter) {
            Store.remove(m.messageID)
        }
    }

    static var mailIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
    }

    /// "Jane <jane@x.com>" -> "jane@x.com"
    static func address(_ raw: String) -> String {
        if let l = raw.lastIndex(of: "<"), let r = raw.lastIndex(of: ">"), l < r {
            return String(raw[raw.index(after: l)..<r])
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }
}
