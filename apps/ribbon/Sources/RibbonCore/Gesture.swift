import Foundation

public enum SwipeEvent: Equatable {
    /// Horizontal movement since the last event, in trackpad widths (0...1 is the full pad).
    case began(dx: Double)
    case changed(dx: Double)
    /// Finger velocity in trackpad widths per second when the fingers lifted.
    case ended(velocity: Double)
}

/// Turns raw multi-finger trackpad frames into horizontal swipe events.
public struct SwipeRecognizer {
    public var fingers: Int
    /// How far (in pad widths) the fingers must travel before a swipe starts.
    public var threshold: Double = 0.025

    enum State: Equatable {
        case idle
        case tracking(startX: Double, startY: Double)
        case swiping(lastX: Double, lastT: Double, velocity: Double)
        case rejected
    }
    var state: State = .idle

    public init(fingers: Int = 3) { self.fingers = fingers }

    public var isSwiping: Bool { if case .swiping = state { return true } else { return false } }

    /// Feeds one frame: number of touching fingers and their average position (0...1, y up).
    public mutating func feed(count: Int, x: Double, y: Double, time: Double) -> SwipeEvent? {
        if count != fingers {
            var ended: Double?
            if case .swiping(_, _, let v) = state { ended = v }
            // Fewer fingers: start over. More fingers: ignore until some lift.
            state = count < fingers ? .idle : .rejected
            return ended.map { .ended(velocity: $0) }
        }
        switch state {
        case .idle:
            state = .tracking(startX: x, startY: y)
            return nil
        case .rejected:
            return nil
        case .tracking(let sx, let sy):
            let dx = x - sx, dy = y - sy
            if abs(dx) > threshold && abs(dx) > 1.4 * abs(dy) {
                state = .swiping(lastX: x, lastT: time, velocity: 0)
                return .began(dx: dx)
            }
            if abs(dy) > threshold * 1.5 && abs(dy) > abs(dx) { state = .rejected }
            return nil
        case .swiping(let lx, let lt, let v):
            let dx = x - lx
            let dt = max(0.001, time - lt)
            let inst = dx / dt
            let nv = v == 0 ? inst : v * 0.6 + inst * 0.4
            state = .swiping(lastX: x, lastT: time, velocity: nv)
            return dx == 0 ? nil : .changed(dx: dx)
        }
    }
}

public enum SwipeMath {
    /// Points of strip travel for a movement of `dx` pad widths.
    public static func points(forPadDelta dx: Double, viewportWidth: Double, sensitivity: Double, natural: Bool) -> Double {
        let p = dx * viewportWidth * 1.6 * sensitivity
        return natural ? -p : p
    }

    /// Rubber-band resistance past the ends of the strip.
    public static func rubberBand(_ scroll: Double, min lo: Double, max hi: Double) -> Double {
        if scroll < lo { return lo - pow(lo - scroll, 0.75) }
        if scroll > hi { return hi + pow(scroll - hi, 0.75) }
        return scroll
    }

    /// After a swipe: the column to focus, given the projected scroll position. Picks the column
    /// whose centre is nearest the middle of the viewport.
    public static func settleColumn(_ s: Strip, _ p: LayoutParams, projectedScroll: Double,
                                    constraints: [WindowID: WindowConstraints] = [:]) -> Int? {
        let g = Layout.geometry(s, p, constraints)
        guard !g.scrolling.isEmpty else { return nil }
        let mid = projectedScroll + g.viewportW / 2
        return g.scrolling.min { a, b in
            abs(g.stripX[a] + g.widths[a] / 2 - mid) < abs(g.stripX[b] + g.widths[b] / 2 - mid)
        }
    }

    public static func scrollLimits(_ s: Strip, _ p: LayoutParams, constraints: [WindowID: WindowConstraints] = [:]) -> (Double, Double) {
        let g = Layout.geometry(s, p, constraints)
        return (0, max(0, g.stripWidth - g.viewportW))
    }
}
