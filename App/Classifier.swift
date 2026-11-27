import Foundation
import FoundationModels

/// Assesses a message with Apple's on-device model (Apple Intelligence / Foundation Models).
/// Nothing leaves the Mac.
@Generable
enum MessageKind {
    case fleeting
    case dated
    case needsAttention
}

@Generable
struct Assessment {
    @Guide(description: """
    fleeting: automated notifications whose value is gone within a day, e.g. alerts, \
    verification codes, social notifications, marketing, newsletters, shipping status updates. \
    dated: relevant until a specific date, then useless, e.g. tickets, bookings, reservations, \
    event invitations, appointment reminders, limited-time offers with an end date. \
    needsAttention: a person or task expects a reply, decision, payment or other action, \
    or it is personal correspondence.
    """)
    var kind: MessageKind

    @Guide(description: "Only for dated: the last date the message matters (e.g. the concert date), as YYYY-MM-DD. Otherwise an empty string.")
    var relevantDate: String

    @Guide(description: "One short sentence explaining the choice.")
    var reason: String
}

@Generable
struct ObsolescenceCheck {
    @Guide(description: "Numbers of the OLDER messages that the newest message makes obsolete. Empty if none.")
    var obsolete: [Int]

    @Guide(description: "One short sentence explaining the choice.")
    var reason: String
}

enum Classifier {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): "Siri model unavailable: \(reason)"
        @unknown default: "Siri model unavailable"
        }
    }

    static func assess(_ m: TrackedMessage) async throws -> (Category, Date?, String) {
        let session = LanguageModelSession(instructions: """
        You sort incoming email so the user's inbox stays clean. Classify the message and, \
        for dated messages, give the date after which it no longer matters. \
        When unsure, choose needsAttention: it is safer to keep a message than to archive it.
        """)
        let dateFmt = ISO8601DateFormatter()
        dateFmt.formatOptions = [.withFullDate]
        let prompt = """
        Today is \(dateFmt.string(from: Date())). The message was received \(dateFmt.string(from: m.received)).
        From: \(m.from)
        Subject: \(m.subject)

        \(m.snippet)
        """
        let result = try await session.respond(to: prompt, generating: Assessment.self)
        let a = result.content
        switch a.kind {
        case .fleeting: return (.fleeting, nil, a.reason)
        case .needsAttention: return (.needsAttention, nil, a.reason)
        case .dated:
            let date = dateFmt.date(from: a.relevantDate.trimmingCharacters(in: .whitespaces))
            return (.dated, date, a.reason)
        }
    }

    /// Which older messages from the same sender does the newest one make obsolete?
    /// (e.g. a newer delivery status, a revised invoice, a newer version of the same newsletter).
    /// Returns indices into `older`.
    static func obsolete(newest: TrackedMessage, older: [TrackedMessage]) async throws -> ([Int], String) {
        let session = LanguageModelSession(instructions: """
        You keep an email inbox tidy. Given the newest message from a sender and some older \
        messages from the same sender, list the older ones that the newest makes obsolete: \
        it replaces, updates, cancels or repeats them, so keeping them adds nothing (e.g. a newer \
        shipping update, a revised bill, this week's edition of the same newsletter, a new code \
        replacing an old one). Do NOT list older messages that are about something different \
        or still need a reply or action. When unsure, leave a message out.
        """)
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        func brief(_ m: TrackedMessage, _ n: Int) -> String {
            "\(m.subject) (\(fmt.string(from: m.received)))\n\(m.snippet.prefix(n))"
        }
        var prompt = "NEWEST from \(newest.from):\n\(brief(newest, 900))\n\nOLDER:\n"
        for (i, m) in older.enumerated() { prompt += "[\(i + 1)] \(brief(m, 250))\n\n" }
        let a = try await session.respond(to: prompt, generating: ObsolescenceCheck.self).content
        let indices = Set(a.obsolete).compactMap { $0 >= 1 && $0 <= older.count ? $0 - 1 : nil }
        return (indices.sorted(), a.reason)
    }
}
