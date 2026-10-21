import Foundation

public enum CleanError: Error, Equatable {
    case empty
    case suspiciouslyLong
}

public enum OutputCleaner {
    /// Lowercased prefixes that models prepend. Longest first so "sure! here is..." wins over "here is...".
    static let preambles: [String] = [
        "sure! here is the corrected text:",
        "sure, here is the corrected text:",
        "here is the corrected text:",
        "here's the corrected text:",
        "here is the corrected version:",
        "here's the corrected version:",
        "corrected text:",
        "corrected version:",
        "corrected:",
    ].sorted { $0.count > $1.count }

    /// Growth allowance: corrected text may be at most 2x the original plus this slack.
    static let lengthSlack = 20

    public static func clean(_ raw: String, original: String) -> Result<String, CleanError> {
        var text = stripThinkBlocks(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripPreamble(text)
        text = stripCodeFence(text)
        text = stripWrappingQuotes(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty { return .failure(.empty) }
        if text.count > original.count * 2 + lengthSlack { return .failure(.suspiciouslyLong) }
        return .success(text)
    }

    static func stripThinkBlocks(_ s: String) -> String {
        s.replacingOccurrences(
            // (?s) lets `.` match newlines; think blocks are usually multi-line.
            of: "(?s)<think>.*?</think>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    static func stripPreamble(_ s: String) -> String {
        let lower = s.lowercased()
        for p in preambles where lower.hasPrefix(p) {
            return String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    static func stripCodeFence(_ s: String) -> String {
        guard s.hasPrefix("```"), s.hasSuffix("```"), s.count >= 6 else { return s }
        var inner = String(s.dropFirst(3).dropLast(3))
        // Drop an optional language tag on the first line, e.g. ```text
        if let firstNewline = inner.firstIndex(of: "\n") {
            let firstLine = inner[inner.startIndex..<firstNewline]
            if !firstLine.contains(" ") && firstLine.count <= 12 {
                inner = String(inner[inner.index(after: firstNewline)...])
            }
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripWrappingQuotes(_ s: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        guard let first = s.first, let last = s.last, s.count >= 2 else { return s }
        for (open, close) in pairs where first == open && last == close {
            let inner = s.dropFirst().dropLast()
            // Only strip if the inner text has no unbalanced instance of the same quote,
            // so `"a" and "b"` is left alone.
            if !inner.contains(open) && !inner.contains(close) {
                return String(inner)
            }
        }
        return s
    }
}
