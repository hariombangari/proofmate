import Foundation

public enum DiffSegment: Equatable {
    case equal(String)
    case deleted(String)
    case inserted(String)
}

public enum WordDiff {
    public static func diff(original: String, corrected: String) -> [DiffSegment] {
        let a = tokens(original)
        let b = tokens(corrected)
        let difference = b.difference(from: a)
        let removed = Set(difference.removals.map(offset))
        let inserted = Set(difference.insertions.map(offset))

        var raw: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                raw.append(.deleted(a[i]))
                i += 1
            } else if j < b.count, inserted.contains(j) {
                raw.append(.inserted(b[j]))
                j += 1
            } else if i < a.count, j < b.count {
                raw.append(.equal(a[i]))
                i += 1
                j += 1
            } else {
                // Defensive: should be unreachable with a valid difference.
                break
            }
        }
        return merge(raw)
    }

    private static func offset(_ change: CollectionDifference<String>.Change) -> Int {
        switch change {
        case .insert(let offset, _, _), .remove(let offset, _, _):
            return offset
        }
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Joins runs of same-kind segments with single spaces.
    static func merge(_ segments: [DiffSegment]) -> [DiffSegment] {
        segments.reduce(into: []) { out, seg in
            switch (out.last, seg) {
            case (.equal(let x)?, .equal(let y)):
                out[out.count - 1] = .equal(x + " " + y)
            case (.deleted(let x)?, .deleted(let y)):
                out[out.count - 1] = .deleted(x + " " + y)
            case (.inserted(let x)?, .inserted(let y)):
                out[out.count - 1] = .inserted(x + " " + y)
            default:
                out.append(seg)
            }
        }
    }
}
