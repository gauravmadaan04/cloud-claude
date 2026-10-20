import Foundation

/// A hand-picked set of files, like a playlist: files stay where they are, and one file can be in many
/// collections. Entries follow files Haven renames or moves; a bookmark finds files moved elsewhere.
public struct FileCollection: Codable, Identifiable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var path: String
        public var added: Date
        /// macOS bookmark data (finds the file after it was moved or renamed outside Haven).
        public var bookmark: Data?

        public init(path: String, added: Date = Date(), bookmark: Data? = nil) {
            self.path = path
            self.added = added
            self.bookmark = bookmark
        }
    }

    public var id: UUID
    public var name: String
    public var symbol: String
    public var entries: [Entry]

    public init(id: UUID = UUID(), name: String, symbol: String = "square.stack", entries: [Entry] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.entries = entries
    }

    public var paths: [String] { entries.map(\.path) }

    public func contains(_ path: String) -> Bool { entries.contains { $0.path == path } }

    /// Adds files not already in the collection. Returns how many were added.
    @discardableResult
    public mutating func add(_ paths: [String], now: Date = Date(), bookmark: (String) -> Data? = { _ in nil }) -> Int {
        var have = Set(entries.map(\.path))
        var added = 0
        for p in paths where have.insert(p).inserted {
            entries.append(Entry(path: p, added: now, bookmark: bookmark(p)))
            added += 1
        }
        return added
    }

    @discardableResult
    public mutating func remove(_ paths: Set<String>) -> Int {
        let before = entries.count
        entries.removeAll { paths.contains($0.path) }
        return before - entries.count
    }

    /// Follows files (and folders, with everything inside them) to their new paths. True when anything changed.
    @discardableResult
    public mutating func follow(_ moves: [String: String]) -> Bool {
        guard !moves.isEmpty else { return false }
        let folderMoves = moves.map { ($0.key.hasSuffix("/") ? $0.key : $0.key + "/", $0.value) }
        var changed = false
        for i in entries.indices {
            let p = entries[i].path
            if let to = moves[p] {
                entries[i].path = to
                changed = true
                continue
            }
            for (from, to) in folderMoves where p.hasPrefix(from) {
                entries[i].path = to + "/" + p.dropFirst(from.count)
                changed = true
                break
            }
        }
        if changed {
            // Two entries can end up on one path (a file moved onto one already listed): keep the first.
            var seen = Set<String>()
            entries = entries.filter { seen.insert($0.path).inserted }
        }
        return changed
    }

    /// The collection's files that are in the index, and the paths that aren't (moved away, or never indexed).
    public func resolve(in index: [FileItem]) -> (found: [FileItem], missing: [String]) {
        let wanted = Set(entries.map(\.path))
        guard !wanted.isEmpty else { return ([], []) }
        let lengths = Set(wanted.map(\.utf8.count))
        var found: [FileItem] = []
        var foundPaths = Set<String>()
        for item in index where lengths.contains(item.path.utf8.count) && wanted.contains(item.path) {
            found.append(item)
            foundPaths.insert(item.path)
            if foundPaths.count == wanted.count { break }
        }
        let missing = entries.map(\.path).filter { !foundPaths.contains($0) }
        return (found, missing)
    }

    /// A name that isn't used yet: "Collection", "Collection 2"…
    public static func freeName(_ base: String, among names: [String]) -> String {
        let taken = Set(names.map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
