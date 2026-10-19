#if os(macOS)
import AppKit
import QuartzCore
import RibbonCore

/// Applies frames to other apps' windows off the main thread. Each app gets its own serial queue,
/// and only the newest frame per window is applied, so a slow app never holds up the others.
final class AXMover {
    private struct Job {
        let element: AXElement
        let frame: Rect
    }

    private let lock = NSLock()
    private var queues: [pid_t: DispatchQueue] = [:]
    private var pending: [pid_t: [WindowID: Job]] = [:]
    private var scheduled = Set<pid_t>()
    private var appliedSize: [WindowID: Size] = [:]

    func set(_ wid: WindowID, pid: pid_t, element: AXElement, frame: Rect) {
        lock.lock()
        pending[pid, default: [:]][wid] = Job(element: element, frame: frame)
        let needsSchedule = !scheduled.contains(pid)
        if needsSchedule { scheduled.insert(pid) }
        let q = queue(for: pid)
        lock.unlock()
        if needsSchedule { q.async { [weak self] in self?.drain(pid) } }
    }

    /// Forget the size we last set, so the next frame sets it again (after a user resize).
    func invalidate(_ wid: WindowID) {
        lock.lock(); appliedSize[wid] = nil; lock.unlock()
    }

    private func queue(for pid: pid_t) -> DispatchQueue {
        if let q = queues[pid] { return q }
        let q = DispatchQueue(label: "ribbon.ax.\(pid)", qos: .userInteractive)
        queues[pid] = q
        return q
    }

    private func drain(_ pid: pid_t) {
        while true {
            lock.lock()
            let batch = pending[pid] ?? [:]
            pending[pid] = [:]
            if batch.isEmpty {
                scheduled.remove(pid)
                lock.unlock()
                return
            }
            var sizes: [WindowID: Size?] = [:]
            for (wid, _) in batch { sizes[wid] = appliedSize[wid] }
            lock.unlock()

            var applied: [WindowID: Size] = [:]
            let app = AXElement.app(pid)
            let enhanced = app.bool("AXEnhancedUserInterface") ?? false
            if enhanced { app.set("AXEnhancedUserInterface", false) }
            for (wid, job) in batch {
                let f = job.frame
                let pos = CGPoint(x: f.x, y: f.y)
                let size = CGSize(width: f.w, height: f.h)
                if let last = sizes[wid] ?? nil, abs(last.w - f.w) < 0.5, abs(last.h - f.h) < 0.5 {
                    job.element.setPosition(pos)
                } else {
                    // Move first, then resize: apps clamp a resize to the screen from wherever the
                    // window currently is, so growing in place can come up short.
                    job.element.setPosition(pos)
                    job.element.setSize(size)
                    if let p = job.element.position, abs(p.x - pos.x) > 1 || abs(p.y - pos.y) > 1 {
                        job.element.setPosition(pos)
                    }
                    // Only remember the size once the app has really taken it; otherwise the next
                    // frame tries again (e.g. once the window has slid somewhere it fits).
                    if let s = job.element.size, abs(s.width - size.width) < 2, abs(s.height - size.height) < 2 {
                        applied[wid] = f.size
                    }
                }
            }
            if enhanced { app.set("AXEnhancedUserInterface", true) }
            lock.lock()
            for (wid, s) in applied { appliedSize[wid] = s }
            lock.unlock()
        }
    }
}

/// Springs windows to their target frames. Runs a timer only while something is moving.
final class Animator {
    struct Target {
        let element: AXElement
        let pid: pid_t
    }

    let mover = AXMover()
    private var anims: [WindowID: FrameAnimation] = [:]
    private var targets: [WindowID: Target] = [:]
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Called with every frame sent to a window (main thread).
    var onFrame: ((WindowID, Rect) -> Void)?
    /// Called when all animations have settled.
    var onSettled: (() -> Void)?

    var isAnimating: Bool { !anims.isEmpty }
    func isAnimating(_ wid: WindowID) -> Bool { anims[wid] != nil }

    func move(_ wid: WindowID, element: AXElement, pid: pid_t, from: Rect?, to: Rect, animated: Bool, response: Double) {
        targets[wid] = Target(element: element, pid: pid)
        guard animated, response > 0.01, let from, !from.isClose(to: to, tolerance: 1) else {
            anims[wid] = nil
            send(wid, to)
            return
        }
        if var a = anims[wid] {
            a.retarget(to)
            anims[wid] = a
        } else {
            anims[wid] = FrameAnimation(from: from, to: to, response: response)
        }
        startTimer()
    }

    func cancel(_ wid: WindowID) {
        anims[wid] = nil
        targets[wid] = nil
    }

    func cancelAll() {
        anims.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// Advances all springs now (called right after a key press so motion starts instantly).
    func kick() { if !anims.isEmpty { tick() } }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, max(1.0 / 240.0, now - lastTick))
        lastTick = now
        var done: [WindowID] = []
        for (wid, var a) in anims {
            a.step(dt)
            anims[wid] = a
            send(wid, a.frame)
            if a.isSettled { done.append(wid) }
        }
        for wid in done { anims[wid] = nil }
        if anims.isEmpty {
            timer?.invalidate()
            timer = nil
            onSettled?()
        }
    }

    private func send(_ wid: WindowID, _ frame: Rect) {
        guard let t = targets[wid] else { return }
        mover.set(wid, pid: t.pid, element: t.element, frame: frame)
        onFrame?(wid, frame)
    }
}
#endif
