import Foundation

/// Rough plain-text extraction from a raw RFC 822 message, enough for the model to judge it.
/// Prefers text/plain, falls back to text/html with tags stripped. Handles base64 and
/// quoted-printable. Not a full MIME parser.
enum MessageText {
    static func extract(_ raw: Data, limit: Int = 3000) -> String {
        let text = String(decoding: raw, as: UTF8.self)
        let parts = leafParts(of: text)
        let plain = parts.first { $0.type.hasPrefix("text/plain") }
        let html = parts.first { $0.type.hasPrefix("text/html") }
        var body = plain.map(decode) ?? html.map { stripHTML(decode($0)) } ?? ""
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(body.prefix(limit))
    }

    private struct Part { var type: String; var encoding: String; var body: String }

    private static func split(_ s: String) -> (headers: String, body: String) {
        for sep in ["\r\n\r\n", "\n\n"] {
            if let r = s.range(of: sep) { return (String(s[..<r.lowerBound]), String(s[r.upperBound...])) }
        }
        return (s, "")
    }

    private static func header(_ name: String, in headers: String) -> String {
        // Unfold continuation lines, then find "Name: value".
        let unfolded = headers.replacingOccurrences(of: #"\r?\n[ \t]+"#, with: " ", options: .regularExpression)
        for line in unfolded.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix(name.lowercased() + ":") {
                return String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func leafParts(of entity: String, depth: Int = 0) -> [Part] {
        let (headers, body) = split(entity)
        let ctype = header("Content-Type", in: headers)
        let lower = ctype.lowercased()
        if lower.hasPrefix("multipart/"), depth < 5,
           let m = ctype.range(of: #"boundary="?([^";]+)"?"#, options: [.regularExpression, .caseInsensitive]) {
            let boundary = String(ctype[m]).replacingOccurrences(of: #"(?i)boundary="?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return body.components(separatedBy: "--" + boundary).dropFirst()
                .filter { !$0.hasPrefix("--") }
                .flatMap { leafParts(of: $0.trimmingCharacters(in: .newlines), depth: depth + 1) }
        }
        return [Part(type: lower.isEmpty ? "text/plain" : lower,
                     encoding: header("Content-Transfer-Encoding", in: headers).lowercased(),
                     body: body)]
    }

    private static func decode(_ p: Part) -> String {
        switch p.encoding {
        case "base64":
            let clean = p.body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: clean).map { String(decoding: $0, as: UTF8.self) } ?? ""
        case "quoted-printable":
            return decodeQP(p.body)
        default:
            return p.body
        }
    }

    private static func decodeQP(_ s: String) -> String {
        var bytes: [UInt8] = []
        let src = Array(s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "").utf8)
        var i = 0
        while i < src.count {
            if src[i] == UInt8(ascii: "="), i + 2 < src.count,
               let b = UInt8(String(decoding: src[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                bytes.append(b); i += 3
            } else {
                bytes.append(src[i]); i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</tr>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
    }
}
