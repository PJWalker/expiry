import MailKit

/// Called by Mail for incoming Inbox messages. MailKit only acts at delivery time, so this
/// just records each message (with a text excerpt) for the app, which assesses it with the
/// on-device model and archives it later. Rules can override or skip the assessment.
final class MessageActionHandler: NSObject, MEMessageActionHandler {
    static let shared = MessageActionHandler()

    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        // Ask Mail to call again once the body has downloaded, so the model can read it.
        guard let raw = message.rawData else {
            completionHandler(.invokeAgainWithBody)
            return
        }
        guard let id = Self.messageID(of: message), !Store.exists(id) else {
            completionHandler(nil)
            return
        }

        let from = message.fromAddress.rawString
        let to = message.toAddresses.map(\.rawString)
        let rule = Store.loadRules().first { $0.matches(from: [from], to: to, subject: message.subject) }
        if rule?.outcome == .ignore {
            DecisionLog.append(.init(messageID: id, subject: message.subject, from: from,
                                     event: "ignored", detail: "Matched an ignore rule"), process: .extension)
            completionHandler(nil)
            return
        }

        // MEMessage has no received date; the handler runs as the message arrives.
        let received = Date()
        var tracked = TrackedMessage(messageID: id, subject: message.subject, from: from,
                                     received: received, snippet: MessageText.extract(raw))
        tracked.apply(rule)   // no rule / .assess: stays unassessed and the app runs the model
        Store.save(tracked)
        DecisionLog.append(.init(tracked, event: tracked.category == .unassessed ? "received" : "decided"), process: .extension)
        completionHandler(nil)
    }

    /// Message-ID header without angle brackets (Mail's AppleScript `message id` omits them).
    static func messageID(of message: MEMessage) -> String? {
        guard let headers = message.headers else { return nil }
        let value = headers.first { $0.key.lowercased() == "message-id" }?.value.first
        return value?.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))
    }
}
