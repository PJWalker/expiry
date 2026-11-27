import Foundation

/// Append-only decision log (JSON lines) in the App Group folder. The extension and the app
/// write separate files so they never append to the same one; the log view merges them.
struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var messageID: String
    var subject: String
    var from: String
    var event: String          // received, decided, overridden, archived, handled, gone, ignored, error
    var category: Category?
    var source: TrackedMessage.Source?
    var archiveAt: Date?
    var detail: String?

    init(messageID: String, subject: String, from: String, event: String, detail: String? = nil) {
        self.messageID = messageID; self.subject = subject; self.from = from
        self.event = event; self.detail = detail
    }

    init(_ m: TrackedMessage, event: String, detail: String? = nil) {
        self.init(messageID: m.messageID, subject: m.subject, from: m.from, event: event, detail: detail ?? m.reason)
        category = m.category; source = m.source; archiveAt = m.archiveAt
    }
}

enum DecisionLog {
    enum Process: String { case app, `extension` }

    static func url(_ p: Process) -> URL { Store.root.appendingPathComponent("log-\(p.rawValue).jsonl") }

    static func append(_ e: LogEntry, process: Process = .app) {
        guard Config.logDecisions else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard var line = try? enc.encode(e) else { return }
        line.append(0x0A)
        let u = url(process)
        if let h = try? FileHandle(forWritingTo: u) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: u)
        }
    }

    /// Newest first.
    static func load(limit: Int = 5000) -> [LogEntry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let all = [Process.app, .extension].flatMap { p -> [LogEntry] in
            guard let text = try? String(contentsOf: url(p), encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? dec.decode(LogEntry.self, from: Data($0.utf8)) }
        }
        return Array(all.sorted { $0.date > $1.date }.prefix(limit))
    }

    static func clear() {
        for p in [Process.app, .extension] { try? FileManager.default.removeItem(at: url(p)) }
    }
}
