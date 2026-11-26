import Foundation

/// File-based store in the shared App Group container.
/// rules.json is written by the app, read by the extension.
/// pending/<hash>.json: one file per expiring message, written by the extension and
/// deleted by the app, so the two processes never edit the same file.
enum Store {
    static var root: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroup)!
    }
    static var rulesURL: URL { root.appendingPathComponent("rules.json") }
    static var pendingDir: URL {
        let d = root.appendingPathComponent("pending", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func loadRules() -> [Rule] {
        guard let data = try? Data(contentsOf: rulesURL) else { return [] }
        return (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
    }

    static func saveRules(_ rules: [Rule]) {
        if let data = try? JSONEncoder().encode(rules) { try? data.write(to: rulesURL, options: .atomic) }
    }

    static func fileURL(for messageID: String) -> URL {
        let safe = Data(messageID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return pendingDir.appendingPathComponent("\(safe).json")
    }

    static func addPending(_ p: PendingMessage) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(p) { try? data.write(to: fileURL(for: p.messageID), options: .atomic) }
    }

    static func loadPending() -> [PendingMessage] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? dec.decode(PendingMessage.self, from: Data(contentsOf: $0)) }
    }

    static func removePending(_ messageID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: messageID))
    }
}
