import MailKit

/// Principal class. Mail asks it for the action handler.
class MailExtension: NSObject, MEExtension {
    func handler(for session: MEExtensionSession) -> MEMessageActionHandler {
        MessageActionHandler.shared
    }
}
