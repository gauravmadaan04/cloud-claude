import Foundation

/// A record of something Haven moved or trashed, so it can be undone later.
public struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable {
        /// `created`: copies Haven made (Make Shareable); undoing one moves the copies to the Trash.
        case trashed, moved, restored, renamed, created
    }

    public struct Move: Codable, Hashable, Sendable {
        public let from: String
        public let to: String
        public let size: Int64
        /// The file's number on disk where it was put, so Undo only ever moves back that same file.
        public let fileID: UInt64?

        public init(from: String, to: String, size: Int64 = 0, fileID: UInt64? = nil) {
            self.from = from
            self.to = to
            self.size = size
            self.fileID = fileID
        }
    }

    public let id: UUID
    public let date: Date
    public let action: Action
    /// Why it happened: "Clean Up · Old Screenshots", "Rule · File screenshots", "Duplicates"…
    public let reason: String
    public let moves: [Move]
    public var undone: Bool

    public init(id: UUID = UUID(), date: Date = Date(), action: Action, reason: String, moves: [Move], undone: Bool = false) {
        self.id = id
        self.date = date
        self.action = action
        self.reason = reason
        self.moves = moves
        self.undone = undone
    }

    public var totalBytes: Int64 { moves.reduce(0) { $0 + $1.size } }

    public var summary: String {
        let n = moves.count
        let things = n == 1 ? ((moves[0].from as NSString).lastPathComponent) : "\(n) items"
        switch action {
        case .trashed: return "Moved \(things) to the Trash"
        case .moved: return "Filed \(things)"
        case .restored: return "Put back \(things)"
        case .renamed: return "Renamed \(things)"
        case .created:
            return n == 1 ? "Made “\((moves[0].to as NSString).lastPathComponent)”" : "Made \(n) files"
        }
    }
}

/// What Haven saves between launches so it opens instantly.
public struct IndexSnapshot: Codable, Sendable {
    public static let currentVersion = 3
    public var version: Int
    public var savedAt: Date
    public var rootPaths: [String]
    public var items: [FileItem]

    public init(rootPaths: [String], items: [FileItem], savedAt: Date = Date()) {
        self.version = IndexSnapshot.currentVersion
        self.savedAt = savedAt
        self.rootPaths = rootPaths
        self.items = items
    }
}

/// A search saved to the sidebar. The text is re-read every time, so "last week" stays current.
public struct SavedSearch: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var text: String
    public var symbol: String

    public init(id: UUID = UUID(), name: String, text: String, symbol: String = "magnifyingglass") {
        self.id = id
        self.name = name
        self.text = text
        self.symbol = symbol
    }

    /// A readable default name: "Screenshots over 5 MB".
    public static func defaultName(for text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let f = t.first else { return "Saved search" }
        return f.uppercased() + t.dropFirst()
    }
}
