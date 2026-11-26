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

    static func assess(_ m: TrackedMessage) async throws -> (Category, Date?) {
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
        case .fleeting: return (.fleeting, nil)
        case .needsAttention: return (.needsAttention, nil)
        case .dated:
            let date = dateFmt.date(from: a.relevantDate.trimmingCharacters(in: .whitespaces))
            return (.dated, date)
        }
    }
}
