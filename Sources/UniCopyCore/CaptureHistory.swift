import Foundation

/// A short, in-memory history of recognised text. Nothing is written to disk and
/// the history disappears when UniCopy quits.
public struct CaptureHistory {
    public let limit: Int
    public private(set) var entries: [String] = []

    public init(limit: Int = 5) {
        self.limit = max(1, limit)
    }

    public var isEmpty: Bool { entries.isEmpty }

    public mutating func add(_ text: String) {
        guard !text.isEmpty else { return }
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    /// Moves an existing entry back to the top after the user copies it again.
    public mutating func promote(_ text: String) {
        guard let index = entries.firstIndex(of: text) else { return }
        entries.remove(at: index)
        entries.insert(text, at: 0)
    }

    public mutating func clear() { entries.removeAll() }

    /// A single-line menu title for a result: whitespace collapsed and clipped
    /// so the menu stays readable even when a capture contains a whole page.
    public static func preview(_ text: String, limit: Int = 48) -> String {
        let single = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let maximum = max(1, limit)
        guard single.count > maximum else { return single }
        let clipped = String(single.prefix(maximum - 1)).trimmingCharacters(in: .whitespaces)
        return clipped + "…"
    }
}
