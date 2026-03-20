import Foundation

enum ContentClassifier {
    static func classify(_ text: String) -> ContentType {
        guard !text.isEmpty else { return .text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n") && looksLikeURL(trimmed) {
            return .link
        }
        let codeScore = codeSignalCount(text)
        if codeScore >= 2 {
            return .code
        }
        return .text
    }

    private static let urlPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^https?://[^\s]+$"#, options: [.caseInsensitive])
    }()

    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return urlPattern.firstMatch(in: trimmed, range: range) != nil
    }

    private static let codeKeywords: Set<String> = [
        "func", "class", "struct", "enum", "protocol", "extension",
        "import", "return", "guard", "switch", "case",
        "let", "var", "const", "def", "fn", "pub",
        "if", "else", "for", "while",
        "async", "await", "throws", "try", "catch",
        "public", "private", "static", "override",
        "self", "nil", "true", "false",
    ]

    private static func codeSignalCount(_ text: String) -> Int {
        var score = 0
        if text.contains("{") && text.contains("}") { score += 1 }
        if text.contains(";") { score += 1 }
        let lines = text.components(separatedBy: .newlines)
        let indentedLines = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }
        if indentedLines.count >= 1 { score += 1 }
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let keywordMatches = words.intersection(codeKeywords).count
        if keywordMatches >= 2 { score += 1 }
        if keywordMatches >= 4 { score += 1 }
        if text.contains("(") && text.contains(")") { score += 1 }
        let assignmentPattern = try? NSRegularExpression(pattern: #"\s[=!<>]=?\s"#)
        let range = NSRange(text.startIndex..., in: text)
        if let matches = assignmentPattern?.numberOfMatches(in: text, range: range), matches > 0 { score += 1 }
        return score
    }
}
