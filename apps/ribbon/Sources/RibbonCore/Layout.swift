import Foundation

public enum CenterMode: String, Codable, CaseIterable, Equatable {
    /// Scroll as little as possible to show the focused column ("edge" scrolling).
    case never
    /// Keep the focused column in the middle of the screen.
    case always
    /// Like `never`, but centre the column when it can't share the screen with the previous one.
    case onOverflow

    public var title: String {
        switch self {
        case .never: return "Scroll just enough"
        case .always: return "Always centre"
        case .onOverflow: return "Centre when it won't fit"
        }
    }
}

public enum SparseAlignment: String, Codable, CaseIterable, Equatable {
    case left, center
    public var title: String { self == .left ? "Start at the left edge" : "Centre on screen" }
}

public enum Visibility: Equatable, Codable {
    case visible
    case partial
    case hidden(Side)

    public var isOnScreen: Bool { if case .hidden = self { return false } else { return true } }
    public var name: String {
        switch self {
        case .visible: return "visible"
        case .partial: return "partial"
        case .hidden(let s): return "hidden-\(s.rawValue)"
        }
    }
}

/// Inputs to the layout that don't belong to the strip itself.
public struct LayoutParams: Equatable {
    /// Display bounds and working area (menu bar and Dock removed), in AX coordinates.
    public var screen: Rect
    public var area: Rect
    public var innerGap: Double
    public var outerGap: Double
    public var centerMode: CenterMode
    public var sparse: SparseAlignment
    public var tabBarHeight: Double
    public var keepOriginalHeight: Bool

    public init(screen: Rect, area: Rect, innerGap: Double = 10, outerGap: Double = 10,
                centerMode: CenterMode = .never, sparse: SparseAlignment = .left,
                tabBarHeight: Double = 28, keepOriginalHeight: Bool = false) {
        self.screen = screen; self.area = area; self.innerGap = innerGap; self.outerGap = outerGap
        self.centerMode = centerMode; self.sparse = sparse; self.tabBarHeight = tabBarHeight
        self.keepOriginalHeight = keepOriginalHeight
    }
}

/// Per-window facts the layout respects: sizes an app refuses to go below, and opening heights.
public struct WindowConstraints: Equatable {
    public var minWidth: Double?
    public var originalHeight: Double?
    public init(minWidth: Double? = nil, originalHeight: Double? = nil) {
        self.minWidth = minWidth; self.originalHeight = originalHeight
    }
}

public struct Placement: Equatable {
    public var window: WindowID
    public var frame: Rect
    public var visibility: Visibility
    public var column: Int
    public var row: Int
}

public struct TabBarPlacement: Equatable {
    public var column: Int
    public var frame: Rect
    public var windows: [WindowID]
    public var active: Int
}

public struct LayoutResult: Equatable {
    public var placements: [Placement] = []
    public var tabBars: [TabBarPlacement] = []
    /// On-screen rectangle of every column (pinned ones included), by column index.
    public var columnRects: [Rect] = []
    public var columnVisibility: [Visibility] = []
    /// The scrolling viewport (area between pinned columns, inside the outer gaps).
    public var viewport: Rect = .zero
    /// Total width of the scrolling columns, gaps included.
    public var stripWidth: Double = 0

    public func placement(for wid: WindowID) -> Placement? { placements.first { $0.window == wid } }
}

public enum Layout {
    /// Pixel width of a column. Fractions are gap-aware so that two 0.5 columns plus one gap
    /// exactly fill the working width.
    public static func pixelWidth(_ fraction: Double, working: Double, gap: Double) -> Double {
        let px = fraction * (working + gap) - gap
        return min(working, max(80, px))
    }

    public static func fraction(forPixelWidth px: Double, working: Double, gap: Double) -> Double {
        guard working + gap > 0 else { return 0.5 }
        return min(1, max(0.05, (px + gap) / (working + gap)))
    }

    static func columnWidth(_ c: Column, p: LayoutParams, working: Double, constraints: [WindowID: WindowConstraints]) -> Double {
        var w = pixelWidth(c.width, working: working, gap: p.innerGap)
        for wid in c.windows {
            if let mw = constraints[wid]?.minWidth { w = max(w, min(mw, working)) }
        }
        return w.rounded()
    }

    /// Scrolling geometry shared by `compute` and `scrollToReveal`.
    struct Geometry {
        var working: Double
        var viewportX: Double       // screen x where scroll offset 0 starts
        var viewportW: Double
        var widths: [Double]        // every column
        var stripX: [Double]        // strip-space x of scrolling columns (pinned: 0)
        var stripWidth: Double
        var leftPinned: [Int]
        var rightPinned: [Int]
        var scrolling: [Int]
    }

    static func geometry(_ s: Strip, _ p: LayoutParams, _ cons: [WindowID: WindowConstraints]) -> Geometry {
        let working = max(100, p.area.w - 2 * p.outerGap)
        let widths = s.columns.map { columnWidth($0, p: p, working: working, constraints: cons) }
        var leftPinned: [Int] = [], rightPinned: [Int] = [], scrolling: [Int] = []
        for (i, c) in s.columns.enumerated() {
            switch c.pin {
            case .left: leftPinned.append(i)
            case .right: rightPinned.append(i)
            case nil: scrolling.append(i)
            }
        }
        let leftW = leftPinned.reduce(0) { $0 + widths[$1] + p.innerGap }
        let rightW = rightPinned.reduce(0) { $0 + widths[$1] + p.innerGap }
        var stripX = Array(repeating: 0.0, count: s.columns.count)
        var x = 0.0
        for i in scrolling { stripX[i] = x; x += widths[i] + p.innerGap }
        let stripWidth = max(0, x - p.innerGap)
        return Geometry(working: working, viewportX: p.area.x + p.outerGap + leftW,
                        viewportW: max(80, working - leftW - rightW), widths: widths, stripX: stripX,
                        stripWidth: stripWidth, leftPinned: leftPinned, rightPinned: rightPinned, scrolling: scrolling)
    }

    /// Returns the scroll offset that shows the focused column according to the centre mode.
    public static func scrollToReveal(_ s: Strip, _ p: LayoutParams,
                                      constraints: [WindowID: WindowConstraints] = [:],
                                      forceCenter: Bool = false) -> Double {
        let g = geometry(s, p, constraints)
        guard !g.scrolling.isEmpty else { return 0 }
        let V = g.viewportW
        if g.stripWidth <= V + 0.5 {
            return p.sparse == .center ? -((V - g.stripWidth) / 2).rounded() : 0
        }
        guard let f = s.focused, s.columns.indices.contains(f), s.columns[f].pin == nil else {
            return clamp(s.scroll, g)
        }
        let x = g.stripX[f], w = g.widths[f]
        let centered = (x + w / 2 - V / 2).rounded()
        if forceCenter || p.centerMode == .always { return centered }

        func minimal(from current: Double) -> Double {
            var sc = current
            if x < sc { sc = x }
            if x + w > sc + V { sc = x + w - V }
            return sc
        }
        switch p.centerMode {
        case .always:
            return centered
        case .never:
            return clamp(minimal(from: s.scroll), g)
        case .onOverflow:
            if let pid = s.previousFocusedColumnID,
               let pi = s.columns.firstIndex(where: { $0.id == pid }), pi != f, s.columns[pi].pin == nil {
                let lo = min(x, g.stripX[pi]), hi = max(x + w, g.stripX[pi] + g.widths[pi])
                if hi - lo > V { return centered }
                // Show both columns, moving as little as possible.
                var sc = s.scroll
                if lo < sc { sc = lo }
                if hi > sc + V { sc = hi - V }
                return clamp(sc, g)
            }
            return clamp(minimal(from: s.scroll), g)
        }
    }

    static func clamp(_ scroll: Double, _ g: Geometry) -> Double {
        let maxScroll = max(0, g.stripWidth - g.viewportW)
        return min(max(0, scroll), maxScroll)
    }

    /// Lays out every window of the strip for the given scroll offset.
    public static func compute(_ s: Strip, _ p: LayoutParams,
                               constraints: [WindowID: WindowConstraints] = [:]) -> LayoutResult {
        let g = geometry(s, p, constraints)
        var r = LayoutResult()
        r.viewport = Rect(x: g.viewportX, y: p.area.y + p.outerGap, w: g.viewportW, h: p.area.h - 2 * p.outerGap)
        r.stripWidth = g.stripWidth
        let top = p.area.y + p.outerGap
        let H = max(100, p.area.h - 2 * p.outerGap)

        // Screen x of every column.
        var screenX = Array(repeating: 0.0, count: s.columns.count)
        var lx = p.area.x + p.outerGap
        for i in g.leftPinned { screenX[i] = lx; lx += g.widths[i] + p.innerGap }
        var rx = p.area.maxX - p.outerGap
        for i in g.rightPinned.reversed() { rx -= g.widths[i]; screenX[i] = rx; rx -= p.innerGap }
        for i in g.scrolling { screenX[i] = (g.viewportX + g.stripX[i] - s.scroll).rounded() }

        let hasLeftPin = !g.leftPinned.isEmpty, hasRightPin = !g.rightPinned.isEmpty
        let visLo = hasLeftPin ? g.viewportX - 1 : p.screen.x
        let visHi = hasRightPin ? g.viewportX + g.viewportW + 1 : p.screen.maxX

        for (ci, col) in s.columns.enumerated() {
            let x = screenX[ci], w = g.widths[ci]
            let colRect = Rect(x: x, y: top, w: w, h: H)
            r.columnRects.append(colRect)
            var vis: Visibility = .visible
            if col.pin == nil {
                if x + w <= visLo + 1 { vis = .hidden(.left) }
                else if x >= visHi - 1 { vis = .hidden(.right) }
                else if x < visLo - 0.5 {
                    vis = hasLeftPin ? .hidden(.left) : .partial
                } else if x + w > visHi + 0.5 {
                    vis = hasRightPin ? .hidden(.right) : .partial
                }
            }
            r.columnVisibility.append(vis)

            switch col.mode {
            case .tabbed where col.windows.count > 1:
                let bar = Rect(x: x, y: top, w: w, h: p.tabBarHeight)
                r.tabBars.append(TabBarPlacement(column: ci, frame: bar, windows: col.windows, active: col.active))
                let frame = Rect(x: x, y: top + p.tabBarHeight, w: w, h: H - p.tabBarHeight)
                for (ri, wid) in col.windows.enumerated() {
                    let v: Visibility = ri == col.active ? vis : .hidden(hiddenSide(vis, x: x, w: w, p: p))
                    r.placements.append(Placement(window: wid, frame: frame, visibility: v, column: ci, row: ri))
                }
            default:
                let n = Double(col.windows.count)
                let avail = H - (n - 1) * p.innerGap
                var y = top
                for (ri, wid) in col.windows.enumerated() {
                    var h = (avail * col.weights[ri]).rounded()
                    if ri == col.windows.count - 1 { h = top + H - y }
                    if col.windows.count == 1, p.keepOriginalHeight,
                       let oh = constraints[wid]?.originalHeight, oh < H, oh > 80 {
                        h = oh.rounded()
                    }
                    r.placements.append(Placement(window: wid, frame: Rect(x: x, y: y, w: w, h: h),
                                                  visibility: vis, column: ci, row: ri))
                    y += h + p.innerGap
                }
            }
        }
        return r
    }

    /// The side a hidden tab or column should be parked on.
    static func hiddenSide(_ v: Visibility, x: Double, w: Double, p: LayoutParams) -> Side {
        if case .hidden(let s) = v { return s }
        return (x + w / 2) < p.screen.midX ? .left : .right
    }

    /// Index of the column whose rectangle is nearest to screen x (used for swipes and drops).
    public static func column(atScreenX sx: Double, in r: LayoutResult) -> Int? {
        guard !r.columnRects.isEmpty else { return nil }
        if let i = r.columnRects.firstIndex(where: { sx >= $0.minX && sx < $0.maxX }) { return i }
        return r.columnRects.indices.min { abs(r.columnRects[$0].midX - sx) < abs(r.columnRects[$1].midX - sx) }
    }

    /// Insertion point (0...count) for a column dropped with its centre at screen x.
    public static func insertionIndex(atScreenX sx: Double, in r: LayoutResult, excluding: Int?) -> Int {
        var idx = 0
        for (i, rect) in r.columnRects.enumerated() where i != excluding {
            if sx > rect.midX { idx = i + 1 }
        }
        return idx
    }
}
