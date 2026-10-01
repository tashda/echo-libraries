import Foundation

/// PEM text: base64 between `-----BEGIN <label>-----` and `-----END <label>-----` lines, as OpenSSL
/// reads it.
enum PEM {
    static func encode(_ der: Data, label: String) -> String {
        let base64 = der.base64EncodedString()
        var lines = ["-----BEGIN \(label)-----"]
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        lines.append("-----END \(label)-----")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The DER of every block with this label.
    static func blocks(in text: String, label: String) -> [Data] {
        let begin = "-----BEGIN \(label)-----", end = "-----END \(label)-----"
        var result: [Data] = []
        var rest = Substring(text)
        while let start = rest.range(of: begin), let stop = rest.range(of: end, range: start.upperBound..<rest.endIndex) {
            let body = rest[start.upperBound..<stop.lowerBound].filter { !$0.isWhitespace }
            if let der = Data(base64Encoded: String(body)) { result.append(der) }
            rest = rest[stop.upperBound...]
        }
        return result
    }

    static func isPEM(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(4096), encoding: .utf8) else { return false }
        return text.contains("-----BEGIN ")
    }
}
