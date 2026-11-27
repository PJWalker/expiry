import AppKit

/// Every 15 min:
/// 1. Assess new messages with the on-device model.
/// 2. For messages past their archive date: if no longer in the Inbox or flagged, they were
///    handled; otherwise move them to the account's archive mailbox. Never deletes.
/// Every decision and action is written to the decision log (if enabled).
@MainActor
final class ExpiryEngine: ObservableObject {
    @Published var messages: [TrackedMessage] = []
    @Published var lastRun: Date?
    @Published var lastError: String?
    @Published var scanStatus: String?
    @Published var busy = false
    private var timer: Timer?

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

    // MARK: Overrides

    func override(_ id: String, category: Category, until: Date? = nil) {
        guard var m = Store.loadAll().first(where: { $0.messageID == id }) else { return }
        m.set(category, source: .user, relevantUntil: until)
        m.reason = nil
        Store.save(m)
        DecisionLog.append(LogEntry(m, event: "overridden"))
        reload()
    }

    /// "Always do this for this sender": adds a rule at the top.
    func addSenderRule(for m: TrackedMessage) {
        var rules = Store.loadRules()
        let outcome: Rule.Outcome = switch m.category {
        case .fleeting: .fleeting
        case .needsAttention, .unassessed: .keep
        case .dated: .assess   // dates differ per message, so keep asking the model
        }
        setSenderRule(m.senderAddress, outcome: outcome, days: 7, supersede: nil, rules: &rules)
        Store.saveRules(rules)
    }

    /// Creates, updates or (with nil outcome and supersede) removes the rule for one sender.
    /// Sender rules go at the top so they beat broader rules.
    func setSenderRule(_ address: String, outcome: Rule.Outcome?, days: Int, supersede: Rule.Supersede?,
                       rules: inout [Rule]) {
        rules.removeAll { $0.senderAddress == address }
        guard outcome != nil || supersede != nil else { return }
        var r = Rule(field: .from, op: .contains, value: address, outcome: outcome ?? .assess)
        r.days = days
        r.supersede = supersede
        rules.insert(r, at: 0)
    }

    // MARK: Rescan

    /// Reads messages already in the Inbox (the extension only sees new arrivals) and assesses them.
    /// - days: how far back to look (0 = everything in the Inbox)
    /// - reassess: also re-run the model on messages it already assessed (your manual choices are kept)
    func rescan(days: Int, reassess: Bool) async {
        guard !busy else { return }
        guard Self.mailIsRunning else { lastError = "Open Mail to rescan."; return }
        busy = true
        defer { busy = false; scanStatus = nil; reload() }
        lastError = nil
        scanStatus = "Reading Inbox…"

        let found: [MailBridge.InboxMessage]
        switch MailBridge.inboxMessages(days: days) {
        case .success(let list): found = list
        case .failure(let err): lastError = "Rescan failed: \(err.localizedDescription)"; return
        }

        let rules = Store.loadRules()
        let existing = Dictionary(Store.loadAll().map { ($0.messageID, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for f in found {
            if let old = existing[f.messageID] {
                guard reassess, old.source == .model else { continue }
            }
            let rule = rules.first { $0.matches(from: [f.from], to: [], subject: f.subject) }
            if rule?.outcome == .ignore { continue }
            var m = TrackedMessage(messageID: f.messageID, subject: f.subject, from: f.from,
                                   received: f.received, snippet: MessageText.clean(f.content))
            m.apply(rule)
            m.clampToFuture()
            Store.save(m)
            DecisionLog.append(LogEntry(m, event: "rescanned"))
            added += 1
        }
        scanStatus = "Assessing \(added) messages…"
        await assessNew()
        scanStatus = "Checking for superseded messages…"
        await checkSuperseded()
        await clearOldColors()
        Task { await self.run() }   // archives anything superseded
        DecisionLog.append(LogEntry(messageID: "", subject: "Rescan", from: "",
                                    event: "rescan", detail: "\(found.count) in Inbox, \(added) assessed"))
    }

    // MARK: Periodic run

    func run() async {
        guard !busy else { return }
        busy = true
        defer { busy = false; lastRun = Date(); reload() }
        lastError = nil

        await assessNew()
        await checkSuperseded()
        forgetOldKept()

        // Don't launch Mail just to check; wait until the user has it open.
        guard Self.mailIsRunning else { return }
        await clearOldColors()

        for m in Store.loadAll() {
            guard let due = m.archiveAt, due <= Date() else { continue }
            switch MailBridge.expire(messageID: m.messageID, archiveMailbox: Config.archiveMailboxName) {
            case .success(let outcome):
                Store.remove(m.messageID)
                let event = switch outcome { case .archived: "archived"; case .handled: "handled"; case .notFound: "gone" }
                DecisionLog.append(LogEntry(m, event: event, detail: outcome == .notFound ? "No longer in Inbox" : nil))
            case .failure(let err):
                lastError = err.localizedDescription
                DecisionLog.append(LogEntry(m, event: "error", detail: err.localizedDescription))
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
        for (i, var m) in pending.enumerated() {
            if scanStatus != nil { scanStatus = "Assessing \(i + 1) of \(pending.count)…" }
            do {
                let (category, date, reason) = try await Classifier.assess(m)
                // Re-read in case the user overrode it while the model was running.
                guard Store.loadAll().first(where: { $0.messageID == m.messageID })?.category == .unassessed else { continue }
                m.set(category, source: .model, relevantUntil: date)
                // A date already in the past (or unparseable) shouldn't archive instantly.
                if category == .dated, let at = m.archiveAt, at < m.received.addingTimeInterval(Config.fleetingInterval) {
                    m.set(.fleeting, source: .model)
                }
                m.reason = reason
                m.clampToFuture()
                Store.save(m)
                DecisionLog.append(LogEntry(m, event: "decided"))
            } catch {
                lastError = "Assessment failed: \(error.localizedDescription)"
                DecisionLog.append(LogEntry(m, event: "error", detail: "Assessment failed: \(error.localizedDescription)"))
            }
        }
    }

    /// For each sender with several tracked messages, ask whether the newest makes the older
    /// ones obsolete; those are archived on this run. A sender rule can force always / never.
    private func checkSuperseded() async {
        let rules = Store.loadRules()
        let all = Store.loadAll().filter { $0.category != .unassessed }
        let groups = Dictionary(grouping: all, by: \.senderAddress)
        for (address, msgs) in groups where msgs.count > 1 {
            let sorted = msgs.sorted { $0.received > $1.received }
            var newest = sorted[0]
            guard newest.supersedeChecked != true else { continue }
            // Don't touch messages you set by hand.
            let older = Array(sorted.dropFirst().filter { $0.source != .user }.prefix(8))
            let setting = rules.first { $0.senderAddress == address }?.supersede ?? .assess

            var obsolete: [TrackedMessage] = []
            var why = ""
            switch setting {
            case .never:
                break
            case .always:
                obsolete = older
                why = "Sender rule: newest replaces older"
            case .assess:
                guard !older.isEmpty, Classifier.isAvailable else { break }
                do {
                    let (idx, reason) = try await Classifier.obsolete(newest: newest, older: older)
                    obsolete = idx.map { older[$0] }
                    why = reason
                } catch {
                    lastError = "Obsolescence check failed: \(error.localizedDescription)"
                    continue   // try again next run
                }
            }

            for var m in obsolete {
                m.archiveAt = Date()
                m.reason = "Superseded by “\(newest.subject)”. \(why)"
                Store.save(m)
                DecisionLog.append(LogEntry(m, event: "superseded"))
            }
            newest.supersedeChecked = true
            Store.save(newest)
        }
    }

    /// Earlier versions colored messages in Mail. Clear any color they left behind.
    private func clearOldColors() async {
        guard Self.mailIsRunning else { return }
        for var m in Store.loadAll() where m.colored {
            if case .success = MailBridge.setColor(messageID: m.messageID, color: "none") {
                m.colored = false
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
}
