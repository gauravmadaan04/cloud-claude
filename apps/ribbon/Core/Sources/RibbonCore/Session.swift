import Foundation

/// What we remember about a window so it can be found again after a restart.
public struct SavedWindow: Codable, Equatable, Hashable {
    public var id: WindowID
    public var bundleID: String?
    public var title: String
    public init(id: WindowID, bundleID: String?, title: String) {
        self.id = id; self.bundleID = bundleID; self.title = title
    }
}

public struct TileSnapshot: Codable, Equatable {
    public var windows: [SavedWindow]
    public var showing: Int
}

/// One screen's windows and choices (window count, layout, sizes).
public struct BoardSnapshot: Codable, Equatable {
    public var displayUUID: String
    public var spaceID: UInt64
    public var spaceIndex: Int
    public var tiles: [TileSnapshot]
    public var layout: LayoutKind?
    public var capacity: Int?
    public var splits: Splits

    public init(displayUUID: String, spaceID: UInt64, spaceIndex: Int, board: Board, ref: (WindowID) -> SavedWindow?) {
        self.displayUUID = displayUUID
        self.spaceID = spaceID
        self.spaceIndex = spaceIndex
        layout = board.layout
        capacity = board.capacity
        splits = board.splits
        tiles = board.tiles.map { t in
            let refs = t.windows.compactMap(ref)
            return TileSnapshot(windows: refs, showing: refs.firstIndex { $0.id == t.showing } ?? 0)
        }
    }
}

public struct SessionSnapshot: Codable, Equatable {
    public var version = 2
    public var savedAt: Date
    public var boards: [BoardSnapshot]

    public init(savedAt: Date = Date(), boards: [BoardSnapshot]) {
        self.savedAt = savedAt; self.boards = boards
    }
}

public enum SessionRestore {
    /// Finds the saved screen for a display + Space: same Space id first (Ribbon restarted),
    /// then the same position in the Space list (Mac restarted, ids changed).
    public static func snapshot(in session: SessionSnapshot, displayUUID: String, spaceID: UInt64, spaceIndex: Int) -> BoardSnapshot? {
        let onDisplay = session.boards.filter { $0.displayUUID == displayUUID }
        return onDisplay.first { $0.spaceID == spaceID } ?? onDisplay.first { $0.spaceIndex == spaceIndex }
    }

    /// Rebuilds a screen from a snapshot using the windows that exist now. Windows are matched by
    /// window number first, then by app + title. Matched windows are added to `used`.
    public static func restore(_ snap: BoardSnapshot, live: [SavedWindow], used: inout Set<WindowID>) -> Board {
        var claimed = Set<WindowID>()
        let liveIDs = Set(live.map(\.id)).subtracting(used)
        func match(_ ref: SavedWindow) -> WindowID? {
            if liveIDs.contains(ref.id), !claimed.contains(ref.id) { claimed.insert(ref.id); return ref.id }
            return nil
        }
        // Pass 1: exact window numbers. Pass 2: same app and title.
        var found: [[WindowID?]] = snap.tiles.map { $0.windows.map(match) }
        for (ti, t) in snap.tiles.enumerated() {
            for (wi, ref) in t.windows.enumerated() where found[ti][wi] == nil {
                if let m = live.first(where: { !claimed.contains($0.id) && !used.contains($0.id) && $0.bundleID != nil
                    && $0.bundleID == ref.bundleID && !ref.title.isEmpty && $0.title == ref.title }) {
                    claimed.insert(m.id)
                    found[ti][wi] = m.id
                }
            }
        }
        var board = Board()
        board.layout = snap.layout
        board.capacity = snap.capacity
        board.splits = snap.splits
        for (ti, t) in snap.tiles.enumerated() {
            let wins = found[ti].compactMap { $0 }
            guard let first = wins.first else { continue }
            var tile = Tile(first)
            for w in wins.dropFirst() { tile.push(w, show: false) }
            if let shown = found[ti].indices.contains(t.showing) ? found[ti][t.showing] : nil { tile.show(shown) }
            board.tiles.append(tile)
        }
        board.active = board.tiles.first?.showing
        used.formUnion(claimed)
        return board
    }
}
