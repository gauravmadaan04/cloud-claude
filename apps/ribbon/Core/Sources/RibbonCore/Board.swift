import Foundation

/// A window's number in the window server (CGWindowID).
public typealias WindowID = UInt32

/// How a screen's tiles are arranged.
public enum LayoutKind: String, Codable, CaseIterable {
    case grid, columns
    public var title: String { self == .grid ? "Grid" : "Columns" }
}

/// One place on the screen. It shows one window; more can wait behind it in a stack.
public struct Tile: Codable, Equatable {
    /// Windows in the order they joined the tile (the order of the grip's segments).
    public private(set) var windows: [WindowID]
    /// The window on top.
    public private(set) var showing: WindowID
    /// Most recently shown first; `recent[0] == showing`. Picks what comes forward when the top window goes.
    private var recent: [WindowID]

    public init(_ wid: WindowID) {
        windows = [wid]; showing = wid; recent = [wid]
    }

    public var isStack: Bool { windows.count > 1 }
    public var showingIndex: Int { windows.firstIndex(of: showing) ?? 0 }
    public func contains(_ wid: WindowID) -> Bool { windows.contains(wid) }
    /// Windows waiting behind the one on top.
    public var waiting: [WindowID] { windows.filter { $0 != showing } }

    /// Adds a window on top.
    public mutating func push(_ wid: WindowID, show: Bool = true) {
        guard !contains(wid) else { if show { self.show(wid) }; return }
        windows.append(wid)
        if show {
            recent.insert(wid, at: 0)
            showing = wid
        } else {
            recent.append(wid)
        }
    }

    @discardableResult
    public mutating func show(_ wid: WindowID) -> Bool {
        guard contains(wid), showing != wid else { return false }
        showing = wid
        recent.removeAll { $0 == wid }
        recent.insert(wid, at: 0)
        return true
    }

    /// Removes a window. Returns false when the tile is left empty.
    @discardableResult
    public mutating func remove(_ wid: WindowID) -> Bool {
        windows.removeAll { $0 == wid }
        recent.removeAll { $0 == wid }
        guard !windows.isEmpty else { return false }
        if showing == wid { showing = recent.first ?? windows[0] }
        return true
    }

    /// Puts `new` exactly where `old` was (a native tab taking its sibling's place, or a swap).
    public mutating func replace(_ old: WindowID, with new: WindowID) {
        guard let i = windows.firstIndex(of: old) else { return }
        if contains(new) { remove(old); return }
        windows[i] = new
        if let r = recent.firstIndex(of: old) { recent[r] = new }
        if showing == old { showing = new }
    }

    /// Shows the next (or previous) window in the stack.
    @discardableResult
    public mutating func cycle(_ step: Int) -> Bool {
        let n = windows.count
        guard n > 1 else { return false }
        return show(windows[((showingIndex + step) % n + n) % n])
    }

    /// Takes out the waiting window that was shown most recently.
    public mutating func popWaiting() -> WindowID? {
        guard let wid = recent.dropFirst().first else { return nil }
        remove(wid)
        return wid
    }
}

/// What happened to a window added to a screen.
public enum AddResult: Equatable {
    case newTile, stacked, full, alreadyThere
}

/// User-set sizes on one screen. They belong to positions, not windows, so they survive swaps.
public struct Splits: Codable, Equatable {
    /// Grid: share of the width taken by the left column.
    public var x = 0.5
    /// Grid with four windows: share of the left column's height taken by the top window.
    public var leftY = 0.5
    /// Grid with three or four windows: share of the right column's height taken by the top window.
    public var rightY = 0.5
    /// Columns and rows: relative sizes (missing entries count as 1).
    public var weights: [Double] = []

    public init() {}

    public func weights(_ n: Int) -> [Double] {
        (0..<n).map { weights.indices.contains($0) ? max(0.05, weights[$0]) : 1 }
    }

    public var isDefault: Bool {
        abs(x - 0.5) < 0.001 && abs(leftY - 0.5) < 0.001 && abs(rightY - 0.5) < 0.001
            && weights.allSatisfy { abs($0 - 1) < 0.001 }
    }
}

/// Everything tiled on one screen (a display in one Space).
public struct Board: Codable, Equatable {
    /// Tiles in position order; the first is the primary.
    public var tiles: [Tile] = []
    /// Grid or columns for this screen; nil follows the setting for all screens.
    public var layout: LayoutKind?
    /// Windows per screen for this screen; nil follows the setting for all screens.
    public var capacity: Int?
    public var splits = Splits()
    /// The window in focus mode, filling the screen.
    public var zoomed: WindowID?
    /// The window last used on this screen.
    public var active: WindowID?

    public init() {}

    public var isEmpty: Bool { tiles.isEmpty }
    public var windows: [WindowID] { tiles.flatMap(\.windows) }
    public var showing: [WindowID] { tiles.map(\.showing) }
    public var windowCount: Int { tiles.reduce(0) { $0 + $1.windows.count } }
    public func contains(_ wid: WindowID) -> Bool { tiles.contains { $0.contains(wid) } }
    public func tileIndex(of wid: WindowID) -> Int? { tiles.firstIndex { $0.contains(wid) } }
    public var activeTile: Int? { active.flatMap { tileIndex(of: $0) } }
    public func isShowing(_ wid: WindowID) -> Bool { tiles.contains { $0.showing == wid } }

    /// Adds a window: in a tile of its own while there's room, else on top of the tile in use.
    @discardableResult
    public mutating func add(_ wid: WindowID, capacity: Int, stackWhenFull: Bool, activate: Bool = true) -> AddResult {
        if contains(wid) { return .alreadyThere }
        let result: AddResult
        if tiles.count < max(1, capacity) {
            tiles.append(Tile(wid))
            result = .newTile
        } else if stackWhenFull {
            let target = activeTile ?? tiles.count - 1
            tiles[target].push(wid)
            result = .stacked
        } else {
            return .full
        }
        if activate { active = wid }
        return result
    }

    /// Puts a window back at a remembered position (after minimising or floating).
    @discardableResult
    public mutating func restore(_ wid: WindowID, at index: Int, capacity: Int, stackWhenFull: Bool) -> AddResult {
        if contains(wid) { return .alreadyThere }
        if tiles.count < max(1, capacity) {
            tiles.insert(Tile(wid), at: min(max(0, index), tiles.count))
            active = wid
            return .newTile
        }
        guard stackWhenFull, !tiles.isEmpty else { return .full }
        tiles[min(max(0, index), tiles.count - 1)].push(wid)
        active = wid
        return .stacked
    }

    /// Removes a window; the others fill its space. Returns false if it wasn't here.
    @discardableResult
    public mutating func remove(_ wid: WindowID) -> Bool {
        guard let i = tileIndex(of: wid) else { return false }
        if !tiles[i].remove(wid) { tiles.remove(at: i) }
        if zoomed == wid { zoomed = nil }
        if active == wid { active = tiles.indices.contains(i) ? tiles[i].showing : tiles.last?.showing }
        return true
    }

    public mutating func replace(_ old: WindowID, with new: WindowID) {
        guard let i = tileIndex(of: old) else { return }
        if contains(new) { remove(old); return }
        tiles[i].replace(old, with: new)
        if active == old { active = new }
        if zoomed == old { zoomed = new }
    }

    /// Exchanges the windows on top of two tiles; stacks stay where they are.
    @discardableResult
    public mutating func swap(_ a: Int, _ b: Int) -> Bool {
        guard a != b, tiles.indices.contains(a), tiles.indices.contains(b) else { return false }
        let wa = tiles[a].showing, wb = tiles[b].showing
        if !tiles[a].isStack && !tiles[b].isStack {
            tiles.swapAt(a, b)
        } else {
            tiles[a].replace(wa, with: wb)
            tiles[b].replace(wb, with: wa)
        }
        return true
    }

    /// Moves the window on top of a tile into the primary position.
    @discardableResult
    public mutating func makePrimary(_ i: Int) -> Bool { swap(i, 0) }

    /// Moves a window onto another tile's stack (⌥⌘-drag).
    @discardableResult
    public mutating func move(_ wid: WindowID, toStackOf target: Int) -> Bool {
        guard let from = tileIndex(of: wid), from != target, tiles.indices.contains(target) else { return false }
        let targetShowing = tiles[target].showing
        remove(wid)
        guard let t = tileIndex(of: targetShowing) else { return false }
        tiles[t].push(wid)
        active = wid
        return true
    }

    /// Puts a window from another screen on top of a tile.
    public mutating func push(_ wid: WindowID, onto i: Int) {
        guard !contains(wid), tiles.indices.contains(i) else { return }
        tiles[i].push(wid)
        active = wid
    }

    /// Shows a window in its stack.
    @discardableResult
    public mutating func show(_ wid: WindowID) -> Bool {
        guard let i = tileIndex(of: wid) else { return false }
        return tiles[i].show(wid)
    }

    @discardableResult
    public mutating func cycle(tile i: Int, _ step: Int) -> Bool {
        guard tiles.indices.contains(i), tiles[i].cycle(step) else { return false }
        active = tiles[i].showing
        return true
    }

    /// Matches the tiles to a new window count: extra tiles join the last one's stack, and with
    /// more room waiting windows get tiles of their own.
    @discardableResult
    public mutating func fit(capacity: Int) -> Bool {
        let cap = max(1, capacity)
        var changed = false
        if tiles.count > cap {
            let keep = tiles[cap - 1].showing
            for t in tiles[cap...] {
                for wid in t.windows { tiles[cap - 1].push(wid, show: false) }
            }
            tiles.removeSubrange(cap...)
            if let a = active, tiles[cap - 1].contains(a) { tiles[cap - 1].show(a) } else { tiles[cap - 1].show(keep) }
            changed = true
        }
        while tiles.count < cap, let i = tiles.lastIndex(where: { $0.isStack }), let wid = tiles[i].popWaiting() {
            tiles.append(Tile(wid))
            changed = true
        }
        return changed
    }

    /// Records the window in use on this screen.
    public mutating func setActive(_ wid: WindowID?) {
        guard let wid else { active = nil; return }
        if contains(wid) { active = wid }
    }
}
