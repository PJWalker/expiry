# Mail Expiry (untested)

Every new Inbox message is assessed by Apple's on-device model (Apple Intelligence, via Foundation Models). The archive date depends on the result:

| Assessment | Example | Archived |
|---|---|---|
| Fleeting | alerts, codes, newsletters, promos | 24h after arrival |
| Until a date | concert ticket, booking, invitation | end of the day after that date |
| Needs attention | a person waiting for a reply, a bill | never |

When unsure, the model is told to pick "needs attention". A message is never deleted, and it isn't archived if by then you've moved it out of the Inbox or flagged it.

## Overrides
- **Rules** (Settings): From / To / Subject, matched with contains / equals / ends with. Each rule picks an outcome: let the model decide, fleeting, archive after N days, keep, or ignore. The first matching rule wins.
- **Per message** (menu bar > Messages…): change the category or date for any message, or choose "Always do this for this sender".

## The window
Menu bar > Open Mail Expiry… opens one window with a sidebar:
- **Messages**: tracked messages, their assessment, the model's reason and archive date, and per-message overrides.
- **Senders**: manual handling per sender. This covers how their messages are treated, and whether a new message replaces older ones (Siri decides, always, or never). It's stored as sender rules at the top of Rules.
- **Rules**: overrides by sender, recipient or subject.
- **Log**: every decision and action (received, decided, overridden, archived, handled, gone, ignored, error), searchable. Logging can be turned off. The log is kept as JSON lines in the App Group folder (Show in Finder).
- **Settings**: archive mailbox, logging, and model and Mail status.

**Rescan Inbox** (toolbar) assesses messages already in the Inbox, from the last 7, 30 or 90 days or the whole Inbox. The extension only sees new arrivals. It skips flagged messages and your manual choices, and can optionally re-assess messages the model already judged. Anything already overdue gets 24 hours' grace, so you can review it before it's archived.

## Older messages from the same sender
When a sender has several messages being tracked, the Siri model checks whether the newest one makes the older ones obsolete. Examples: a newer shipping update, a revised bill, this week's newsletter. Obsolete ones are archived on the same run. Your manual choices and flagged messages are never touched. When unsure, the model keeps a message. Each sender's newest message is checked once, and at most 8 older messages are compared with it.

## How it works
- **Mail extension (MailKit action handler)**: MailKit can only act when a message arrives. The extension waits for the body, saves the sender, subject and a text excerpt to the shared App Group folder, and applies any matching rule.
- **Menu bar app**: every 15 min it assesses new messages with the model and archives overdue ones through AppleScript. It only touches Mail while Mail is running.
- The text excerpt is used only by the on-device model. Kept messages are forgotten after 14 days.

## Build
1. `brew install xcodegen && xcodegen` in this folder, open `MailExpiry.xcodeproj`.
2. Team ID is set in `project.yml` and `Config.appGroup` (`Shared/Models.swift`). Change both together if the team changes.
3. Run the app, then enable the extension in Mail > Settings > Extensions.
4. Allow Automation access to Mail when macOS asks.

Distribution: Developer ID (outside the App Store), since the app scripts Mail.

## Requirements
macOS 26+ with Apple Intelligence turned on. Without it, messages stay unassessed and nothing is archived, apart from rule matches.

## Known limits / guesses
- **Due date / "Remind Me" is not detected.** As far as I can tell Mail's AppleScript doesn't expose it. Flagging works.
- Extension sees only messages delivered to an Inbox (per developer reports); messages filtered elsewhere are skipped.
- Archive mailbox is looked up by name per account ("Archive" by default; Gmail: `[Gmail]/All Mail`).
- Inbox lookup uses mailbox `INBOX` of each account — unverified for every account type.
- If a dated message has no usable date, it is kept. If its date is already past, it is treated as fleeting.
- The text extraction is a rough MIME parser, which is enough for the model.
- Not compiled yet: written without a Mac.
