import Foundation

/// Talks to Mail.app through AppleScript (Apple Events). Needs the user's one-time
/// Automation permission (System Settings > Privacy & Security > Automation).
enum MailBridge {
    enum Outcome: String { case archived, handled, notFound }

    struct ScriptError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Archive the message unless it was handled (moved out of the Inbox, or flagged).
    static func expire(messageID: String, archiveMailbox: String) -> Result<Outcome, Error> {
        run(inInbox: messageID, body: """
                    if flagged status of m then
                        set background color of m to none
                        return "handled"
                    end if
                    set background color of m to none
                    -- Errors here (e.g. no archive mailbox) surface to the app instead of being swallowed.
                    move m to mailbox "\(escape(archiveMailbox))" of acct
                    return "archived"
        """).map { Outcome(rawValue: $0) ?? .notFound }
    }

    /// color: none, orange, yellow, ... (Mail's AppleScript background colors).
    static func setColor(messageID: String, color: String) -> Result<Void, Error> {
        run(inInbox: messageID, body: """
                    set background color of m to \(color)
                    return "handled"
        """).map { _ in () }
    }

    /// Finds the message in each account's INBOX and runs `body` with `m` and `acct` bound.
    private static func run(inInbox messageID: String, body: String) -> Result<String, Error> {
        let script = """
        tell application "Mail"
            repeat with acct in every account
                set hits to {}
                try
                    set hits to (messages of mailbox "INBOX" of acct whose message id is "\(escape(messageID))")
                end try
                if (count of hits) > 0 then
                    set m to item 1 of hits
        \(body)
                end if
            end repeat
            return "notFound"
        end tell
        """
        var errInfo: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&errInfo) else {
            return .failure(ScriptError(message: (errInfo?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"))
        }
        return .success(result.stringValue ?? "notFound")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
