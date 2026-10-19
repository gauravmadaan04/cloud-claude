import Foundation

/// A macOS window number (CGWindowID).
public typealias WindowID = UInt32

public enum ColumnMode: String, Codable, Equatable {
    case stacked, tabbed
}

/// One column of the strip: one window, or several stacked vertically (or shown as tabs).
public struct Column: Codable, Equatable, Identifiable {
    public var id: UUID
    public var windows: [WindowID]
    /// Vertical share of each window in a stack; same count as `windows`, sums to 1.
    public var weights: [Double]
    /// Width as a fraction of the display's working width (gap-aware, see `Layout.pixelWidth`).
    public var width: Double
    public var mode: ColumnMode
    /// Index of the focused window inside the column.
    public var active: Int
    public var pin: Side?
    /// Width to go back to when "full width" is toggled off.
    public var savedWidth: Double?

    public init(window: WindowID, width: Double) {
        self.init(windows: [window], width: width)
    }

    public init(windows: [WindowID], width: Double, weights: [Double]? = nil,
                mode: ColumnMode = .stacked, active: Int = 0, pin: Side? = nil) {
        self.id = UUID()
        self.windows = windows
        self.width = width
        self.mode = mode
        self.active = min(max(0, active), max(0, windows.count - 1))
        self.pin = pin
        if let weights, weights.count == windows.count, weights.allSatisfy({ $0 > 0 }) {
            self.weights = Column.normalized(weights)
        } else {
            self.weights = Array(repeating: 1.0 / Double(max(1, windows.count)), count: windows.count)
        }
    }

    public var activeWindow: WindowID? { windows.indices.contains(active) ? windows[active] : windows.first }

    static func normalized(_ w: [Double]) -> [Double] {
        let s = w.reduce(0, +)
        guard s > 0 else { return Array(repeating: 1.0 / Double(max(1, w.count)), count: w.count) }
        return w.map { $0 / s }
    }

    mutating func equalize() {
        weights = Array(repeating: 1.0 / Double(max(1, windows.count)), count: windows.count)
    }

    mutating func insert(_ wid: WindowID, at index: Int) {
        let i = min(max(0, index), windows.count)
        let share = 1.0 / Double(windows.count + 1)
        weights = weights.map { $0 * (1 - share) }
        windows.insert(wid, at: i)
        weights.insert(share, at: i)
        weights = Column.normalized(weights)
    }

    mutating func remove(at index: Int) {
        guard windows.indices.contains(index) else { return }
        windows.remove(at: index)
        weights.remove(at: index)
        weights = Column.normalized(weights)
        if active >= windows.count { active = max(0, windows.count - 1) }
        else if active > index { active -= 1 }
    }
}

/// A horizontal strip of columns for one display + Space. Columns are kept in visual order:
/// left-pinned columns first, then the scrolling columns, then right-pinned columns.
public struct Strip: Codable, Equatable {
    public var columns: [Column] = []
    /// Index of the focused column.
    public var focused: Int?
    /// Viewport offset into the scrolling part of the strip, in points.
    public var scroll: Double = 0
    /// Column focused before the current one (used by "centre on overflow" and focus-back).
    public var previousFocusedColumnID: UUID?
    public var previousFocusedWindow: WindowID?

    public init() {}

    public var isEmpty: Bool { columns.isEmpty }
    public var allWindows: [WindowID] { columns.flatMap { $0.windows } }
    public var windowCount: Int { columns.reduce(0) { $0 + $1.windows.count } }

    public var focusedColumn: Column? {
        guard let f = focused, columns.indices.contains(f) else { return nil }
        return columns[f]
    }

    public var focusedWindow: WindowID? { focusedColumn?.activeWindow }

    public func locate(_ wid: WindowID) -> (column: Int, row: Int)? {
        for (ci, c) in columns.enumerated() {
            if let ri = c.windows.firstIndex(of: wid) { return (ci, ri) }
        }
        return nil
    }

    public func contains(_ wid: WindowID) -> Bool { locate(wid) != nil }

    // MARK: Groups (pinned left / scrolling / pinned right)

    func group(of index: Int) -> Range<Int> {
        let pin = columns[index].pin
        let lo = columns.firstIndex { $0.pin == pin } ?? index
        let hi = columns.lastIndex { $0.pin == pin } ?? index
        return lo..<(hi + 1)
    }

    /// Index where a new scrolling column goes at the end of the scrolling group.
    var scrollingEnd: Int {
        (columns.lastIndex { $0.pin == nil }).map { $0 + 1 } ?? (columns.lastIndex { $0.pin == .left }.map { $0 + 1 } ?? 0)
    }

    var scrollingStart: Int {
        (columns.firstIndex { $0.pin == nil }) ?? (columns.lastIndex { $0.pin == .left }.map { $0 + 1 } ?? 0)
    }

    // MARK: Focus

    mutating func setFocus(column: Int, row: Int? = nil) {
        guard columns.indices.contains(column) else { return }
        if let f = focused, f != column, columns.indices.contains(f) {
            previousFocusedColumnID = columns[f].id
            previousFocusedWindow = columns[f].activeWindow
        } else if focused == column, let r = row, r != columns[column].active {
            previousFocusedWindow = columns[column].activeWindow
        }
        focused = column
        if let r = row, columns[column].windows.indices.contains(r) { columns[column].active = r }
    }

    @discardableResult
    public mutating func focus(window wid: WindowID) -> Bool {
        guard let (c, r) = locate(wid) else { return false }
        if focused == c && columns[c].active == r { return false }
        setFocus(column: c, row: r)
        return true
    }

    @discardableResult
    public mutating func focusColumn(_ index: Int) -> Bool {
        guard columns.indices.contains(index), focused != index else { return false }
        setFocus(column: index)
        return true
    }

    @discardableResult
    public mutating func focusLeft() -> Bool {
        guard let f = focused else { return focusColumn(0) }
        return f > 0 ? focusColumn(f - 1) : false
    }

    @discardableResult
    public mutating func focusRight() -> Bool {
        guard let f = focused else { return focusColumn(0) }
        return f + 1 < columns.count ? focusColumn(f + 1) : false
    }

    @discardableResult
    public mutating func focusFirst() -> Bool { focusColumn(0) }

    @discardableResult
    public mutating func focusLast() -> Bool { focusColumn(columns.count - 1) }

    /// Moves focus up/down inside the focused column (tabs wrap around).
    @discardableResult
    public mutating func focusVertical(_ delta: Int) -> Bool {
        guard let f = focused else { return false }
        let c = columns[f]
        guard c.windows.count > 1 else { return false }
        var n = c.active + delta
        if c.mode == .tabbed { n = (n % c.windows.count + c.windows.count) % c.windows.count }
        guard c.windows.indices.contains(n), n != c.active else { return false }
        previousFocusedWindow = c.activeWindow
        columns[f].active = n
        return true
    }

    // MARK: Adding and removing windows

    public enum InsertPosition { case afterFocused, end, start, index(Int) }

    /// Adds a window as a new column. Returns the column index.
    @discardableResult
    public mutating func insert(_ wid: WindowID, width: Double, at position: InsertPosition = .afterFocused, focus: Bool) -> Int {
        let col = Column(window: wid, width: width)
        var idx: Int
        switch position {
        case .end: idx = scrollingEnd
        case .start: idx = scrollingStart
        case .index(let i): idx = min(max(scrollingStart, i), scrollingEnd)
        case .afterFocused:
            if let f = focused, columns.indices.contains(f), columns[f].pin == nil { idx = f + 1 }
            else { idx = scrollingEnd }
        }
        columns.insert(col, at: idx)
        if let f = focused, f >= idx { focused = f + 1 }
        if focus || focused == nil { setFocus(column: idx) }
        return idx
    }

    /// Removes a window. Returns true if it was in this strip.
    @discardableResult
    public mutating func remove(_ wid: WindowID) -> Bool {
        guard let (c, r) = locate(wid) else { return false }
        if previousFocusedWindow == wid { previousFocusedWindow = nil }
        if columns[c].windows.count > 1 {
            columns[c].remove(at: r)
            return true
        }
        let removedID = columns[c].id
        columns.remove(at: c)
        if previousFocusedColumnID == removedID { previousFocusedColumnID = nil }
        if columns.isEmpty {
            focused = nil
            scroll = 0
        } else if let f = focused {
            if f > c { focused = f - 1 }
            else if f == c {
                // Prefer the window that was focused before, otherwise the left neighbour.
                if let pid = previousFocusedColumnID, let pi = columns.firstIndex(where: { $0.id == pid }) {
                    focused = pi
                } else {
                    focused = max(0, min(c - 1, columns.count - 1))
                }
            }
        }
        return true
    }

    /// Replaces a window in place (used when a native tab takes over from its sibling).
    @discardableResult
    public mutating func replace(_ old: WindowID, with new: WindowID) -> Bool {
        guard let (c, r) = locate(old) else { return false }
        columns[c].windows[r] = new
        if previousFocusedWindow == old { previousFocusedWindow = new }
        return true
    }

    // MARK: Moving

    /// Moves the focused column one step left (-1) or right (+1) inside its pin group.
    @discardableResult
    public mutating func moveColumn(_ delta: Int) -> Bool {
        guard let f = focused else { return false }
        let g = group(of: f)
        let t = f + delta
        guard g.contains(t) else { return false }
        columns.swapAt(f, t)
        focused = t
        return true
    }

    @discardableResult
    public mutating func moveColumnToEdge(last: Bool) -> Bool {
        guard let f = focused else { return false }
        let g = group(of: f)
        let t = last ? g.upperBound - 1 : g.lowerBound
        guard t != f else { return false }
        let col = columns.remove(at: f)
        columns.insert(col, at: t)
        focused = t
        return true
    }

    /// Moves column `from` to the insertion point `to` (0...count, in the current indexing),
    /// staying inside its pin group. Used by drag and drop.
    @discardableResult
    public mutating func moveColumn(from: Int, to: Int) -> Bool {
        guard columns.indices.contains(from) else { return false }
        let focusedID = focusedColumn?.id
        let col = columns.remove(at: from)
        var t = to > from ? to - 1 : to
        let leftEnd = columns.lastIndex { $0.pin == .left }.map { $0 + 1 } ?? 0
        let rightStart = columns.firstIndex { $0.pin == .right } ?? columns.count
        switch col.pin {
        case .left: t = min(max(0, t), leftEnd)
        case nil: t = min(max(leftEnd, t), rightStart)
        case .right: t = min(max(rightStart, t), columns.count)
        }
        columns.insert(col, at: t)
        if let id = focusedID { focused = columns.firstIndex { $0.id == id } }
        return t != from
    }

    /// Moves the focused window up/down inside its stack.
    @discardableResult
    public mutating func moveWindowVertical(_ delta: Int) -> Bool {
        guard let f = focused else { return false }
        let a = columns[f].active, t = a + delta
        guard columns[f].windows.indices.contains(t) else { return false }
        columns[f].windows.swapAt(a, t)
        columns[f].weights.swapAt(a, t)
        columns[f].active = t
        return true
    }

    /// Stacks the focused window into the neighbouring column on `side`.
    @discardableResult
    public mutating func consume(into side: Side) -> Bool {
        guard let f = focused else { return false }
        let t = side == .left ? f - 1 : f + 1
        guard columns.indices.contains(t), let wid = columns[f].activeWindow else { return false }
        let targetID = columns[t].id
        let sourceWasSingle = columns[f].windows.count == 1
        columns[f].remove(at: columns[f].active)
        if sourceWasSingle { columns.remove(at: f) }
        guard let ti = columns.firstIndex(where: { $0.id == targetID }) else { return false }
        columns[ti].insert(wid, at: columns[ti].windows.count)
        columns[ti].active = columns[ti].windows.count - 1
        focused = ti
        return true
    }

    /// Pops the focused window out of its stack into a new column on `side`.
    @discardableResult
    public mutating func expel(to side: Side) -> Bool {
        guard let f = focused, columns[f].windows.count > 1, let wid = columns[f].activeWindow else { return false }
        var col = Column(window: wid, width: columns[f].width)
        col.pin = columns[f].pin
        columns[f].remove(at: columns[f].active)
        let idx = side == .left ? f : f + 1
        columns.insert(col, at: idx)
        previousFocusedColumnID = columns[side == .left ? f + 1 : f].id
        focused = idx
        return true
    }

    // MARK: Sizing

    @discardableResult
    public mutating func cycleWidth(presets: [Double], forward: Bool = true) -> Bool {
        guard let f = focused, !presets.isEmpty else { return false }
        let p = presets.sorted()
        let w = columns[f].width
        let next: Double
        if forward { next = p.first { $0 > w + 0.01 } ?? p[0] }
        else { next = p.last { $0 < w - 0.01 } ?? p[p.count - 1] }
        columns[f].width = next
        columns[f].savedWidth = nil
        return true
    }

    @discardableResult
    public mutating func adjustWidth(by delta: Double) -> Bool {
        guard let f = focused else { return false }
        let w = min(1.0, max(0.1, columns[f].width + delta))
        guard abs(w - columns[f].width) > 0.0001 else { return false }
        columns[f].width = w
        columns[f].savedWidth = nil
        return true
    }

    @discardableResult
    public mutating func setWidth(_ w: Double, column: Int? = nil) -> Bool {
        guard let c = column ?? focused, columns.indices.contains(c) else { return false }
        columns[c].width = min(1.0, max(0.05, w))
        return true
    }

    @discardableResult
    public mutating func toggleFullWidth() -> Bool {
        guard let f = focused else { return false }
        if columns[f].width >= 0.999, let s = columns[f].savedWidth {
            columns[f].width = s
            columns[f].savedWidth = nil
        } else {
            columns[f].savedWidth = columns[f].width
            columns[f].width = 1.0
        }
        return true
    }

    /// Grows (positive) or shrinks (negative) the focused window inside its stack.
    @discardableResult
    public mutating func adjustHeight(by delta: Double) -> Bool {
        guard let f = focused, columns[f].windows.count > 1, columns[f].mode == .stacked else { return false }
        var c = columns[f]
        let n = Double(c.windows.count)
        let minShare = min(0.1, 1.0 / n)
        let cur = c.weights[c.active]
        let target = min(1 - minShare * (n - 1), max(minShare, cur + delta))
        guard abs(target - cur) > 0.0001 else { return false }
        let othersOld = 1 - cur, othersNew = 1 - target
        for i in c.weights.indices where i != c.active {
            c.weights[i] = othersOld > 0 ? c.weights[i] / othersOld * othersNew : othersNew / (n - 1)
        }
        c.weights[c.active] = target
        c.weights = Column.normalized(c.weights)
        columns[f] = c
        return true
    }

    /// Sets the share of one window in its stack, scaling the others to fill the rest.
    public mutating func setWeight(window wid: WindowID, share: Double) {
        guard let (c, r) = locate(wid), columns[c].windows.count > 1 else { return }
        let n = Double(columns[c].windows.count)
        let s = min(1 - 0.05 * (n - 1), max(0.05, share))
        let othersOld = 1 - columns[c].weights[r]
        for i in columns[c].weights.indices where i != r {
            columns[c].weights[i] = othersOld > 0 ? columns[c].weights[i] / othersOld * (1 - s) : (1 - s) / (n - 1)
        }
        columns[c].weights[r] = s
        columns[c].weights = Column.normalized(columns[c].weights)
    }

    @discardableResult
    public mutating func equalizeHeights() -> Bool {
        guard let f = focused, columns[f].windows.count > 1 else { return false }
        columns[f].equalize()
        return true
    }

    @discardableResult
    public mutating func toggleTabbed() -> Bool {
        guard let f = focused else { return false }
        columns[f].mode = columns[f].mode == .stacked ? .tabbed : .stacked
        return true
    }

    /// Pins the focused column to `side`, or unpins it if already pinned there.
    @discardableResult
    public mutating func togglePin(_ side: Side) -> Bool {
        guard let f = focused else { return false }
        var col = columns.remove(at: f)
        if col.pin == side {
            col.pin = nil
            let idx = side == .left ? scrollingStart : scrollingEnd
            columns.insert(col, at: idx)
            focused = idx
        } else {
            col.pin = side
            let idx: Int
            if side == .left { idx = columns.lastIndex { $0.pin == .left }.map { $0 + 1 } ?? 0 }
            else { idx = columns.count }
            columns.insert(col, at: idx)
            focused = idx
        }
        return true
    }

    /// Drops windows that are not in `alive` (safety net for missed close notifications).
    public mutating func prune(keeping alive: Set<WindowID>) -> [WindowID] {
        let dead = allWindows.filter { !alive.contains($0) }
        for d in dead { remove(d) }
        return dead
    }

    /// Repairs invariants after decoding or bulk edits.
    public mutating func normalize() {
        columns.removeAll { $0.windows.isEmpty }
        for i in columns.indices {
            if columns[i].weights.count != columns[i].windows.count { columns[i].equalize() }
            columns[i].active = min(max(0, columns[i].active), columns[i].windows.count - 1)
        }
        let left = columns.filter { $0.pin == .left }
        let mid = columns.filter { $0.pin == nil }
        let right = columns.filter { $0.pin == .right }
        let fid = focusedColumn?.id
        columns = left + mid + right
        if let fid { focused = columns.firstIndex { $0.id == fid } }
        if columns.isEmpty { focused = nil }
        else if focused == nil || !columns.indices.contains(focused!) { focused = 0 }
    }
}
