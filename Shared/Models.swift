import Foundation

/// How a message is treated. Set by the on-device model, a rule, or the user.
enum Category: String, Codable, CaseIterable {
    case unassessed      // waiting for the model
    case fleeting        // notification: archive after a day
    case dated           // relevant until a fixed date: archive after it
    case needsAttention  // needs a reply or action: stays in the Inbox

    var label: String {
        switch self {
        case .unassessed: "Not assessed yet"
        case .fleeting: "Fleeting (1 day)"
        case .dated: "Until a date"
        case .needsAttention: "Needs attention (keep)"
        }
    }
}

/// A manual override. The first enabled rule that matches decides; no match = let the model assess.
struct Rule: Codable, Identifiable, Hashable {
    enum Field: String, Codable, CaseIterable { case from, to, subject }
    enum Op: String, Codable, CaseIterable { case contains, equals, endsWith }
    enum Outcome: String, Codable, CaseIterable {
        case assess, fleeting, afterDays, keep, ignore
        var label: String {
            switch self {
            case .assess: "Let Siri model decide"
            case .fleeting: "Fleeting (1 day)"
            case .afterDays: "Archive after N days"
            case .keep: "Keep (never archive)"
            case .ignore: "Ignore completely"
            }
        }
    }

    var id = UUID()
    var enabled = true
    var field: Field = .from
    var op: Op = .contains
    var value = ""
    var outcome: Outcome = .fleeting
    var days = 7

    func matches(from: [String], to: [String], subject: String) -> Bool {
        guard enabled, !value.isEmpty else { return false }
        let candidates: [String]
        switch field {
        case .from: candidates = from
        case .to: candidates = to
        case .subject: candidates = [subject]
        }
        let v = value.lowercased()
        return candidates.contains { raw in
            let s = raw.lowercased()
            switch op {
            case .contains: return s.contains(v)
            case .equals: return s == v
            case .endsWith: return s.hasSuffix(v)
            }
        }
    }
}

/// An incoming Inbox message the extension recorded.
struct TrackedMessage: Codable, Identifiable {
    enum Source: String, Codable { case model, rule, user }

    var messageID: String      // RFC 822 Message-ID without angle brackets
    var subject: String
    var from: String
    var received: Date
    var snippet: String        // plain-text excerpt, only for on-device assessment
    var category: Category = .unassessed
    var source: Source = .model
    var relevantUntil: Date?   // for .dated: last day the message matters
    var archiveAt: Date?       // nil = never archive
    var colored = false        // Mail background color applied for current category
    var reason: String?        // model's one-line explanation, if any

    var id: String { messageID }

    /// Old messages (e.g. from a rescan) whose archive date already passed get a day's grace,
    /// so nothing is archived before you've had a chance to see the decision.
    mutating func clampToFuture(now: Date = Date()) {
        if let a = archiveAt, a < now { archiveAt = now.addingTimeInterval(Config.fleetingInterval) }
    }

    /// Applies a matching rule's outcome. Leaves the message unassessed for .assess / no rule.
    mutating func apply(_ rule: Rule?) {
        switch rule?.outcome {
        case .fleeting?:
            set(.fleeting, source: .rule)
        case .keep?:
            set(.needsAttention, source: .rule)
        case .afterDays?:
            category = .dated
            source = .rule
            archiveAt = received.addingTimeInterval(TimeInterval(rule!.days) * 86_400)
        default:
            break
        }
        if rule != nil, category != .unassessed { reason = "Rule: \(rule!.field.rawValue) \(rule!.op.rawValue) \"\(rule!.value)\"" }
    }

    /// Sets category and recomputes the archive date.
    mutating func set(_ category: Category, source: Source, relevantUntil: Date? = nil, now: Date = Date()) {
        self.category = category
        self.source = source
        self.relevantUntil = relevantUntil
        self.colored = false
        switch category {
        case .unassessed, .needsAttention:
            archiveAt = nil
        case .fleeting:
            archiveAt = received.addingTimeInterval(Config.fleetingInterval)
        case .dated:
            // "A concert ticket is relevant until the day after the concert":
            // archive at the end of the day after the relevant date.
            if let d = relevantUntil {
                let cal = Calendar.current
                archiveAt = cal.date(byAdding: .day, value: 1 + Config.datedGraceDays, to: cal.startOfDay(for: d))
            } else {
                // GUESS: no usable date -> keep, so nothing is archived by mistake.
                self.category = .needsAttention
                archiveAt = nil
            }
        }
    }
}

enum Config {
    static let appGroup = "JKTY8WVAP5.com.example.mailexpiry"   // must match entitlements: <Team ID>.<suffix>
    static let fleetingInterval: TimeInterval = 24 * 60 * 60
    static let datedGraceDays = 1
    /// Kept messages (no archive date) are forgotten after this long.
    static let forgetKeptAfter: TimeInterval = 14 * 24 * 60 * 60
    /// Name of the archive mailbox in each account. GUESS: "Archive" works for iCloud/most IMAP;
    /// Gmail users should set "[Gmail]/All Mail".
    static var archiveMailboxName: String {
        UserDefaults(suiteName: appGroup)?.string(forKey: "archiveMailbox") ?? "Archive"
    }
    /// Decision logging, on by default.
    static var logDecisions: Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: "logDecisions") as? Bool ?? true
    }
}
