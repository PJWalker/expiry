import MailKit

/// Principal class. Mail asks it for the message action handler.
class MailExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> MEMessageActionHandler {
        MessageActionHandler.shared
    }
}
