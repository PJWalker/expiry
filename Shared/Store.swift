import Foundation

/// File-based store in the shared App Group container.
/// rules.json: written by the app, read by the extension.
/// messages/<hash>.json: one file per tracked message. The extension creates it once;
/// after that only the app updates or deletes it.
enum Store {
    static var root: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroup)!
    }
    static var rulesURL: URL { root.appendingPathComponent("rules.json") }
    static var messagesDir: URL {
        let d = root.appendingPathComponent("messages", isDirectory: true)
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
        return messagesDir.appendingPathComponent("\(safe).json")
    }

    static func exists(_ messageID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: messageID).path)
    }

    static func save(_ m: TrackedMessage) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(m) { try? data.write(to: fileURL(for: m.messageID), options: .atomic) }
    }

    static func loadAll() -> [TrackedMessage] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: messagesDir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? dec.decode(TrackedMessage.self, from: Data(contentsOf: $0)) }
    }

    static func remove(_ messageID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: messageID))
    }
}
