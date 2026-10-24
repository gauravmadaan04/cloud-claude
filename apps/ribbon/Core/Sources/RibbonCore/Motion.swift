import Foundation

/// A critically damped spring, evaluated analytically so any frame rate gives the same motion.
public struct Spring: Equatable {
    public var value: Double
    public var velocity: Double
    public var target: Double
    /// Rough settle time in seconds.
    public var response: Double

    public init(value: Double, target: Double, response: Double = 0.28, velocity: Double = 0) {
        self.value = value; self.target = target; self.response = response; self.velocity = velocity
    }

    public var isSettled: Bool { abs(value - target) < 0.5 && abs(velocity) < 8 }

    public mutating func step(_ dt: Double) {
        guard response > 0.001 else { value = target; velocity = 0; return }
        let omega = 2 * Double.pi / response
        let x0 = value - target
        let v0 = velocity
        let e = exp(-omega * dt)
        value = target + (x0 + (v0 + omega * x0) * dt) * e
        velocity = (v0 - omega * (v0 + omega * x0) * dt) * e
        if isSettled { value = target; velocity = 0 }
    }
}

/// Animates a window's origin towards a target frame. Sizes are applied straight away because
/// resizing other apps' windows every frame is slow; positions glide.
public struct FrameAnimation: Equatable {
    public var x: Spring
    public var y: Spring
    public var size: Size

    public init(from: Rect, to: Rect, response: Double) {
        x = Spring(value: from.x, target: to.x, response: response)
        y = Spring(value: from.y, target: to.y, response: response)
        size = to.size
    }

    public var frame: Rect { Rect(x: x.value.rounded(), y: y.value.rounded(), w: size.w, h: size.h) }
    public var target: Rect { Rect(x: x.target, y: y.target, w: size.w, h: size.h) }
    public var isSettled: Bool { x.isSettled && y.isSettled }

    public mutating func retarget(_ to: Rect) {
        x.target = to.x; y.target = to.y; size = to.size
    }

    public mutating func step(_ dt: Double) {
        x.step(dt); y.step(dt)
    }
}
