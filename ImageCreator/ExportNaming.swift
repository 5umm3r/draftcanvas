import Foundation

enum ExportNaming {
    private static let invalidChars = CharacterSet(charactersIn: "/\\:?*\"<>|")
    private static let maxLength = 64

    static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = trimmed.unicodeScalars.map { scalar -> Character in
            invalidChars.contains(scalar) ? "_" : Character(scalar)
        }.reduce(into: "") { $0.append($1) }
        s = s.replacingOccurrences(of: " ", with: "_")
        if s.isEmpty { s = "Untitled" }
        if s.count > maxLength { s = String(s.prefix(maxLength)) }
        return s
    }

    static func baseFilename(forProjectName projectName: String, ordinal: Int) -> String {
        let safe = sanitize(projectName)
        return String(format: "%@-%02d", safe, ordinal)
    }
}
