import MailKit

/// Called by Mail for incoming Inbox messages (MailKit only runs at delivery time;
/// it cannot act on messages later). Matching messages get an orange background
/// and are recorded so the app can archive them after 24h.
final class MessageActionHandler: NSObject, MEMessageActionHandler {
    static let shared = MessageActionHandler()

    func decideAction(for message: MEMessage, completionHandler: @escaping (MEMessageActionDecision?) -> Void) {
        let rules = Store.loadRules()
        let from = [message.fromAddress.rawString]
        let to = message.toAddresses.map(\.rawString)
        let subject = message.subject

        guard rules.contains(where: { $0.matches(from: from, to: to, subject: subject) }),
              let id = Self.messageID(of: message) else {
            completionHandler(nil)
            return
        }

        Store.addPending(PendingMessage(messageID: id, subject: subject,
                                        received: message.dateReceived ?? Date()))
        completionHandler(.action(.setBackgroundColor(.orange)))
    }

    /// Message-ID header without angle brackets (Mail's AppleScript `message id` omits them).
    static func messageID(of message: MEMessage) -> String? {
        guard let headers = message.headers else { return nil }
        let value = headers.first { $0.key.lowercased() == "message-id" }?.value.first
        return value?.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))
    }
}
