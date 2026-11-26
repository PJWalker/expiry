import Foundation

/// One user criterion. A message expires if ANY enabled rule matches (OR).
struct Rule: Codable, Identifiable, Hashable {
    enum Field: String, Codable, CaseIterable { case from, to, subject }
    enum Op: String, Codable, CaseIterable { case contains, equals, endsWith }

    var id = UUID()
    var enabled = true
    var field: Field = .from
    var op: Op = .contains
    var value = ""

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

/// A message the extension marked as expiring.
struct PendingMessage: Codable {
    var messageID: String      // RFC 822 Message-ID without angle brackets
    var subject: String
    var received: Date
    var deadline: Date { received.addingTimeInterval(Config.expiryInterval) }
}

enum Config {
    static let appGroup = "TEAMID.com.example.mailexpiry"   // TODO: must match entitlements (Team ID prefix)
    static let expiryInterval: TimeInterval = 24 * 60 * 60
    /// Name of the archive mailbox in each account. GUESS: "Archive" works for iCloud/most IMAP;
    /// Gmail users should set "[Gmail]/All Mail".
    static var archiveMailboxName: String {
        UserDefaults(suiteName: appGroup)?.string(forKey: "archiveMailbox") ?? "Archive"
    }
}
