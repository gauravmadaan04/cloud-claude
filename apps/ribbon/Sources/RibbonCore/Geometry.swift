import Foundation

/// A rectangle in global screen coordinates with the origin at the top-left of the main display
/// and y growing downwards (the coordinate space used by the Accessibility API).
public struct Rect: Codable, Equatable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public static let zero = Rect(x: 0, y: 0, w: 0, h: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var center: Point { Point(x: midX, y: midY) }
    public var size: Size { Size(w: w, h: h) }
    public var area: Double { max(0, w) * max(0, h) }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }

    public func intersection(_ o: Rect) -> Rect? {
        let nx = max(x, o.x), ny = max(y, o.y)
        let mx = min(maxX, o.maxX), my = min(maxY, o.maxY)
        guard mx > nx, my > ny else { return nil }
        return Rect(x: nx, y: ny, w: mx - nx, h: my - ny)
    }

    public func intersectionArea(_ o: Rect) -> Double { intersection(o)?.area ?? 0 }

    public func insetBy(_ d: Double) -> Rect { Rect(x: x + d, y: y + d, w: w - 2 * d, h: h - 2 * d) }

    public func rounded() -> Rect { Rect(x: x.rounded(), y: y.rounded(), w: w.rounded(), h: h.rounded()) }

    /// True when every edge is within `tolerance` points of the other rectangle's.
    public func isClose(to o: Rect, tolerance: Double = 2) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance &&
            abs(w - o.w) <= tolerance && abs(h - o.h) <= tolerance
    }

    public var description: String { "(\(Int(x)),\(Int(y)) \(Int(w))x\(Int(h)))" }
}

public struct Point: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Size: Codable, Equatable, Hashable {
    public var w: Double
    public var h: Double
    public init(w: Double, h: Double) { self.w = w; self.h = h }
}

public enum Side: String, Codable, Equatable, Hashable {
    case left, right
}
