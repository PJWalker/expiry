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

    struct InboxMessage { var messageID, subject, from: String; var received: Date; var content: String }

    /// Unflagged messages in every account's INBOX received in the last `days` days (0 = all).
    static func inboxMessages(days: Int) -> Result<[InboxMessage], Error> {
        // days = 0 drops the date condition (locale-independent; no date literal needed).
        let script = """
        on clip(t)
            if length of t > 3000 then return text 1 thru 3000 of t
            return t
        end clip
        tell application "Mail"
            set out to {}
            set cutoff to (current date) - (\(max(days, 0)) * days)
            repeat with acct in every account
                set ms to {}
                try
                    set ms to (messages of mailbox "INBOX" of acct whose \(days > 0 ? "date received > cutoff and " : "")flagged status is false)
                end try
                repeat with m in ms
                    try
                        set c to ""
                        try
                            set c to my clip(content of m)
                        end try
                        set end of out to {message id of m, subject of m, sender of m, date received of m, c}
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
        var errInfo: NSDictionary?
        guard let list = NSAppleScript(source: script)?.executeAndReturnError(&errInfo) else {
            return .failure(ScriptError(message: (errInfo?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"))
        }
        guard list.numberOfItems > 0 else { return .success([]) }
        var out: [InboxMessage] = []
        for i in 1...list.numberOfItems {
            guard let row = list.atIndex(i), row.numberOfItems == 5,
                  let id = row.atIndex(1)?.stringValue, let date = row.atIndex(4)?.dateValue else { continue }
            out.append(InboxMessage(messageID: id, subject: row.atIndex(2)?.stringValue ?? "",
                                    from: row.atIndex(3)?.stringValue ?? "", received: date,
                                    content: row.atIndex(5)?.stringValue ?? ""))
        }
        return .success(out)
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
