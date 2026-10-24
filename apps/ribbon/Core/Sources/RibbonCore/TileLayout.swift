import Foundation

/// How tiles are placed on a particular screen.
public enum Arrangement: String, Equatable {
    case grid, columns, rows
}

public enum Direction: String, Codable, CaseIterable {
    case left, right, up, down
}

/// The geometry of every layout. Pure functions, so they are easy to test and to preview.
public enum TileLayout {
    /// No split goes below this share of its space.
    public static let minShare = 0.15

    /// Tall screens always stack windows in rows.
    public static func arrangement(_ kind: LayoutKind, area: Rect) -> Arrangement {
        if area.h > area.w * 1.1 { return .rows }
        return kind == .grid ? .grid : .columns
    }

    /// The most tiles a screen takes: a laptop fits three columns, a big monitor four.
    public static func maxTiles(_ a: Arrangement, area: Rect) -> Int {
        switch a {
        case .grid: return 4
        case .columns: return area.w >= 1900 ? 4 : 3
        case .rows: return 3
        }
    }

    public static func capacity(requested: Int, _ a: Arrangement, area: Rect) -> Int {
        max(1, min(requested, maxTiles(a, area: area)))
    }

    /// Splits `total` points into pieces with `gap` between them, in proportion to `shares`,
    /// giving each piece at least its minimum when they can all fit.
    public static func split(_ total: Double, gap: Double, shares: [Double], mins: [Double]) -> [Double] {
        let n = shares.count
        guard n > 0 else { return [] }
        let avail = max(0, total - gap * Double(n - 1))
        let sum = shares.reduce(0, +)
        var sizes = shares.map { sum > 0 ? avail * $0 / sum : avail / Double(n) }
        let m = (0..<n).map { mins.indices.contains($0) ? max(0, mins[$0]) : 0 }
        guard m.reduce(0, +) <= avail + 0.5 else { return sizes }
        var fixed = Set<Int>()
        for _ in 0..<n {
            let short = (0..<n).filter { !fixed.contains($0) && sizes[$0] < m[$0] - 0.01 }
            if short.isEmpty { break }
            for i in short { sizes[i] = m[i]; fixed.insert(i) }
            let free = (0..<n).filter { !fixed.contains($0) }
            let left = avail - fixed.reduce(0) { $0 + sizes[$1] }
            let freeShare = free.reduce(0) { $0 + shares[$1] }
            for i in free { sizes[i] = freeShare > 0 ? left * shares[i] / freeShare : left / Double(free.count) }
        }
        return sizes
    }

    /// Which tiles share the left and right columns of the grid.
    public static func gridColumns(_ n: Int) -> (left: [Int], right: [Int]) {
        switch n {
        case 0, 1: return ([0], [])
        case 2: return ([0], [1])
        case 3: return ([0], [1, 2])
        default: return ([0, 3], [1, 2])
        }
    }

    /// Frames for `count` tiles in `area` (already inset by the outer spacing). `mins` are the
    /// smallest sizes the windows in each tile accept.
    public static func frames(count: Int, _ a: Arrangement, area: Rect, gap: Double, splits: Splits, mins: [Size] = []) -> [Rect] {
        guard count > 0 else { return [] }
        func mw(_ i: Int) -> Double { mins.indices.contains(i) ? mins[i].w : 0 }
        func mh(_ i: Int) -> Double { mins.indices.contains(i) ? mins[i].h : 0 }
        let A = area
        switch a {
        case .columns:
            let ws = split(A.w, gap: gap, shares: splits.weights(count), mins: (0..<count).map(mw))
            var x = A.x
            return ws.map { w in defer { x += w + gap }; return Rect(x: x, y: A.y, w: w, h: A.h) }
        case .rows:
            let hs = split(A.h, gap: gap, shares: splits.weights(count), mins: (0..<count).map(mh))
            var y = A.y
            return hs.map { h in defer { y += h + gap }; return Rect(x: A.x, y: y, w: A.w, h: h) }
        case .grid:
            if count == 1 { return [A] }
            let n = min(count, 4)
            let (left, right) = gridColumns(n)
            let lmin = left.map(mw).max() ?? 0, rmin = right.map(mw).max() ?? 0
            let ws = split(A.w, gap: gap, shares: [splits.x, 1 - splits.x], mins: [lmin, rmin])
            let lx = A.x, rx = A.x + ws[0] + gap
            var out = [Rect](repeating: .zero, count: n)
            func column(_ idx: [Int], x: Double, w: Double, share: Double) {
                if idx.count == 1 {
                    out[idx[0]] = Rect(x: x, y: A.y, w: w, h: A.h)
                    return
                }
                let hs = split(A.h, gap: gap, shares: [share, 1 - share], mins: [mh(idx[0]), mh(idx[1])])
                out[idx[0]] = Rect(x: x, y: A.y, w: w, h: hs[0])
                out[idx[1]] = Rect(x: x, y: A.y + hs[0] + gap, w: w, h: hs[1])
            }
            column(left, x: lx, w: ws[0], share: splits.leftY)
            column(right, x: rx, w: ws[1], share: splits.rightY)
            return out
        }
    }

    /// True when every tile is at least as big as its windows need.
    public static func fits(_ frames: [Rect], mins: [Size]) -> Bool {
        for (i, f) in frames.enumerated() where mins.indices.contains(i) {
            if f.w < mins[i].w - 1 || f.h < mins[i].h - 1 { return false }
        }
        return true
    }

    /// The nearest tile in a direction, preferring the one that lines up best.
    public static func neighbor(of i: Int, _ dir: Direction, in frames: [Rect]) -> Int? {
        guard frames.indices.contains(i) else { return nil }
        let f = frames[i]
        var best: (index: Int, key: [Double])?
        for (j, g) in frames.enumerated() where j != i {
            let dist: Double, overlap: Double
            switch dir {
            case .left:
                guard g.maxX <= f.minX + 2 else { continue }
                dist = f.minX - g.maxX; overlap = min(f.maxY, g.maxY) - max(f.minY, g.minY)
            case .right:
                guard g.minX >= f.maxX - 2 else { continue }
                dist = g.minX - f.maxX; overlap = min(f.maxY, g.maxY) - max(f.minY, g.minY)
            case .up:
                guard g.maxY <= f.minY + 2 else { continue }
                dist = f.minY - g.maxY; overlap = min(f.maxX, g.maxX) - max(f.minX, g.minX)
            case .down:
                guard g.minY >= f.maxY - 2 else { continue }
                dist = g.minY - f.maxY; overlap = min(f.maxX, g.maxX) - max(f.minX, g.minX)
            }
            guard overlap > 1 else { continue }
            let key = [dist.rounded(), -overlap.rounded(), g.minY, g.minX]
            if best == nil || key.lexicographicallyPrecedes(best!.key) { best = (j, key) }
        }
        return best?.index
    }

    /// The tile under a point.
    public static func tile(at p: Point, in frames: [Rect]) -> Int? {
        frames.firstIndex { $0.contains(p) }
    }

    private static func clampShare(_ v: Double) -> Double { min(1 - minShare, max(minShare, v)) }

    /// Makes one tile bigger (positive delta) or smaller. Returns nil when it can't change further.
    public static func resized(_ s: Splits, tile i: Int, by delta: Double, count: Int, _ a: Arrangement) -> Splits? {
        var out = s
        switch a {
        case .grid:
            guard count > 1 else { return nil }
            let (left, right) = gridColumns(min(count, 4))
            let inLeft = left.contains(i)
            out.x = clampShare(s.x + (inLeft ? delta : -delta))
            let col = inLeft ? left : right
            if col.count == 2 {
                let top = col[0] == i
                if inLeft { out.leftY = clampShare(s.leftY + (top ? delta : -delta)) }
                else { out.rightY = clampShare(s.rightY + (top ? delta : -delta)) }
            }
        case .columns, .rows:
            guard count > 1, (0..<count).contains(i) else { return nil }
            var w = s.weights(count)
            let total = w.reduce(0, +)
            w = w.map { $0 / total }
            let lo = minShare / Double(count) * 2
            let target = min(1 - lo * Double(count - 1), max(lo, w[i] + delta))
            let rest = 1 - w[i]
            let newRest = 1 - target
            for j in 0..<count where j != i { w[j] = rest > 0 ? w[j] * newRest / rest : newRest / Double(count - 1) }
            w[i] = target
            out.weights = w.map { $0 * Double(count) }
        }
        return out == s ? nil : out
    }

    /// Reads the sizes a user set by dragging the edge of tile `i` from `old` to `new`.
    public static func splits(afterResizing i: Int, from old: Rect, to new: Rect, count: Int, _ a: Arrangement,
                              area A: Rect, gap: Double, splits s: Splits) -> Splits {
        var out = s
        switch a {
        case .grid:
            guard count > 1 else { return s }
            let (left, right) = gridColumns(min(count, 4))
            let inLeft = left.contains(i)
            let usable = max(1, A.w - gap)
            let leftWidth = inLeft ? new.maxX - A.x : new.minX - gap - A.x
            if abs(inLeft ? new.maxX - old.maxX : new.minX - old.minX) > 1 { out.x = clampShare(leftWidth / usable) }
            let col = inLeft ? left : right
            if col.count == 2 {
                let top = col[0] == i
                let usableH = max(1, A.h - gap)
                let moved = top ? abs(new.maxY - old.maxY) : abs(new.minY - old.minY)
                if moved > 1 {
                    let topH = top ? new.maxY - A.y : new.minY - gap - A.y
                    if inLeft { out.leftY = clampShare(topH / usableH) } else { out.rightY = clampShare(topH / usableH) }
                }
            }
        case .columns, .rows:
            guard count > 1 else { return s }
            let horizontal = a == .columns
            let current = frames(count: count, a, area: A, gap: gap, splits: s)
            var sizes = current.map { horizontal ? $0.w : $0.h }
            let lowMoved = horizontal ? abs(new.minX - old.minX) : abs(new.minY - old.minY)
            let highMoved = horizontal ? abs(new.maxX - old.maxX) : abs(new.maxY - old.maxY)
            if highMoved >= lowMoved, i < count - 1 {
                let edge = horizontal ? new.maxX : new.maxY
                let start = horizontal ? current[i].minX : current[i].minY
                let pair = sizes[i] + sizes[i + 1]
                sizes[i] = min(pair * (1 - minShare), max(pair * minShare, edge - start))
                sizes[i + 1] = pair - sizes[i]
            } else if lowMoved > highMoved, i > 0 {
                let edge = horizontal ? new.minX : new.minY
                let start = horizontal ? current[i - 1].minX : current[i - 1].minY
                let pair = sizes[i - 1] + sizes[i]
                sizes[i - 1] = min(pair * (1 - minShare), max(pair * minShare, edge - gap - start))
                sizes[i] = pair - sizes[i - 1]
            } else {
                return s
            }
            let mean = sizes.reduce(0, +) / Double(count)
            out.weights = sizes.map { $0 / max(1, mean) }
        }
        return out
    }
}
