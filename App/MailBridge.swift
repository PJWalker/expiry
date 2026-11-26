import Foundation

/// Talks to Mail.app through AppleScript (Apple Events). Needs the user's one-time
/// Automation permission (System Settings > Privacy & Security > Automation).
enum MailBridge {
    enum Outcome: String { case archived, handled, notFound, keep }

    struct ScriptError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func expire(messageID: String, archiveMailbox: String) -> Result<Outcome, Error> {
        let script = """
        tell application "Mail"
            repeat with acct in every account
                set hits to {}
                try
                    set hits to (messages of mailbox "INBOX" of acct whose message id is "\(escape(messageID))")
                end try
                if (count of hits) > 0 then
                    set m to item 1 of hits
                    if flagged status of m then
                        set background color of m to none
                        return "handled"
                    end if
                    -- Errors here (e.g. no archive mailbox) surface to the app instead of being swallowed.
                    set background color of m to none
                    move m to mailbox "\(escape(archiveMailbox))" of acct
                    return "archived"
                end if
            end repeat
            return "notFound"
        end tell
        """
        var errInfo: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&errInfo) else {
            return .failure(ScriptError(message: (errInfo?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"))
        }
        return .success(Outcome(rawValue: result.stringValue ?? "") ?? .keep)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
