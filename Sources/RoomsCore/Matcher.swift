import Foundation

public struct Match: Sendable, Equatable {
    public let room: Room
    /// 0…1. 1 is an exact name; lower scores are looser matches.
    public let score: Double
}

/// Finds rooms from what you type. Deterministic and instant: short input like
/// "ds" never needs a model.
public enum Matcher {
    /// Lowercase, no accents, Cyrillic read as Latin: "Café" → "cafe", "Привет" → "privet".
    public static func fold(_ s: String) -> String {
        let latin = s.applyingTransform(.toLatin, reverse: false) ?? s
        return latin
            .replacingOccurrences(of: "đ", with: "dj")
            .replacingOccurrences(of: "Đ", with: "Dj")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// Best matches first. An empty query lists every room, most recently used first.
    public static func rank(_ query: String, rooms: [Room], recency: [String: Date] = [:]) -> [Match] {
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        let matches: [Match]
        if q.isEmpty {
            matches = rooms.map { Match(room: $0, score: 0) }
        } else {
            matches = rooms.compactMap { room in
                let best = ([room.name] + room.aliases).compactMap { score(q, fold($0)) }.max()
                return best.map { Match(room: room, score: $0) }
            }
        }
        return matches.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let ra = recency[a.room.id] ?? .distantPast, rb = recency[b.room.id] ?? .distantPast
            if ra != rb { return ra > rb }
            return a.room.name.localizedStandardCompare(b.room.name) == .orderedAscending
        }
    }

    /// Scores one folded query against one folded candidate, or nil when it doesn't match.
    static func score(_ q: String, _ c: String) -> Double? {
        guard !q.isEmpty, !c.isEmpty else { return nil }
        let ratio = Double(q.count) / Double(max(c.count, q.count))
        if q == c { return 1 }
        if c.hasPrefix(q) { return 0.9 + 0.05 * ratio }

        let words = c.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 0.8 + 0.05 * ratio }

        let initials = String(words.compactMap(\.first))
        if q.count >= 2, initials.hasPrefix(q) { return 0.75 }

        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1, tokens.allSatisfy({ t in words.contains(where: { $0.hasPrefix(t) }) }) { return 0.7 }

        if q.count >= 2, isSubsequence(q, of: c) { return 0.4 + 0.2 * ratio }
        return nil
    }

    private static func isSubsequence(_ q: String, of c: String) -> Bool {
        var it = c.makeIterator()
        return q.allSatisfy { ch in
            while let next = it.next() { if next == ch { return true } }
            return false
        }
    }
}
