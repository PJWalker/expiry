# Mail Expiry (v1 scaffold, untested)

Messages matching your rules get an orange background in Mail. If not handled within 24h they are moved to the account's archive mailbox. Nothing is deleted.

## How it works
- **Mail extension (MailKit action handler)**: runs when a message arrives in an Inbox. If any rule matches (From / To / Subject; contains / equals / ends with), it colors the message orange and records its Message-ID in the shared App Group folder. MailKit cannot act on messages later, so it does nothing else.
- **Menu bar app**: edits rules, and every 15 min checks messages past their 24h deadline through AppleScript:
  - not in Inbox any more (archived, moved, deleted) → handled, forgotten
  - flagged → handled, color cleared
  - otherwise → moved to the archive mailbox
- Only checks while Mail is running; overdue messages are archived on the next check after Mail opens.

## Build
1. `brew install xcodegen && xcodegen` in this folder, open `MailExpiry.xcodeproj`.
2. Set your Team ID and bundle prefix in `project.yml`, and `Config.appGroup` in `Shared/Models.swift` to `<TEAMID>.com.example.mailexpiry`.
3. Run the app, then enable the extension in Mail > Settings > Extensions.
4. Allow Automation access to Mail when macOS asks.

Distribution: Developer ID (outside the App Store), since the app scripts Mail.

## Known limits / guesses
- **Due date / "Remind Me" is not detected.** As far as I can tell Mail's AppleScript doesn't expose it. Flagging works.
- Extension sees only messages delivered to an Inbox (per developer reports); messages filtered elsewhere are skipped.
- Archive mailbox is looked up by name per account ("Archive" by default; Gmail: `[Gmail]/All Mail`).
- Inbox lookup uses mailbox `INBOX` of each account — unverified for every account type.
- Not compiled yet: written without a Mac.
