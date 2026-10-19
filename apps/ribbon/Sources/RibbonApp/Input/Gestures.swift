#if os(macOS)
import AppKit
import QuartzCore
import RibbonCore

/// Reads raw finger positions from the built-in and Magic trackpads through the private
/// MultitouchSupport framework (what MiddleClick, Jitouch and BetterTouchTool use), and turns
/// three- or four-finger horizontal swipes into strip scrolling.
final class TrackpadWatcher {
    static let shared = TrackpadWatcher()

    typealias DeviceRef = UnsafeMutableRawPointer
    typealias ContactCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterFn = @convention(c) (DeviceRef, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (DeviceRef, Int32) -> Void
    private typealias StopFn = @convention(c) (DeviceRef) -> Void

    private let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private var devices: [AnyObject] = []
    private let lock = NSLock()
    private var recognizer = SwipeRecognizer(fingers: 3)
    private(set) var isRunning = false
    var isAvailable: Bool { handle != nil }
    var deviceCount: Int { devices.count }

    /// Swipe events, delivered on the main thread.
    var onSwipe: ((SwipeEvent) -> Void)?

    private func fn<T>(_ name: String) -> T? {
        guard let h = handle, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    func start(fingers: Int) {
        lock.lock(); recognizer = SwipeRecognizer(fingers: fingers); lock.unlock()
        guard !isRunning else { return }
        guard let create: CreateListFn = fn("MTDeviceCreateList"),
              let register: RegisterFn = fn("MTRegisterContactFrameCallback"),
              let startDev: StartFn = fn("MTDeviceStart"),
              let list = create()?.takeRetainedValue() as? [AnyObject] else {
            Log.info("Trackpad gestures unavailable")
            return
        }
        devices = list
        for d in devices {
            let ref = Unmanaged.passUnretained(d).toOpaque()
            register(ref, trackpadContactCallback)
            startDev(ref, 0)
        }
        isRunning = !devices.isEmpty
        Log.info("Trackpad gestures on \(devices.count) device(s), \(fingers) fingers")
    }

    func stop() {
        guard isRunning, let stopDev: StopFn = fn("MTDeviceStop") else { isRunning = false; return }
        for d in devices { stopDev(Unmanaged.passUnretained(d).toOpaque()) }
        devices.removeAll()
        isRunning = false
    }

    /// Re-scan devices (after sleep or when a Magic Trackpad connects).
    func restart() {
        let cfg = SettingsStore.shared.config
        stop()
        if cfg.swipeEnabled && cfg.tilingEnabled { start(fingers: cfg.swipeFingers) }
    }

    fileprivate func frame(_ data: UnsafeMutableRawPointer?, count: Int32, time: Double) {
        var sx = 0.0, sy = 0.0
        var n = 0
        if let data {
            for i in 0..<Int(count) {
                let base = data.advanced(by: i * 96)
                let state = base.load(fromByteOffset: 20, as: Int32.self)
                // 1-2: hovering/starting, 3-4: touching, 5-7: lifting.
                guard state >= 3 && state <= 4 else { continue }
                sx += Double(base.load(fromByteOffset: 32, as: Float.self))
                sy += Double(base.load(fromByteOffset: 36, as: Float.self))
                n += 1
            }
        }
        let x = n > 0 ? sx / Double(n) : 0, y = n > 0 ? sy / Double(n) : 0
        lock.lock()
        let ev = recognizer.feed(count: n, x: x, y: y, time: time)
        lock.unlock()
        if let ev { DispatchQueue.main.async { self.onSwipe?(ev) } }
    }
}

private let trackpadContactCallback: TrackpadWatcher.ContactCallback = { _, data, count, timestamp, _ in
    TrackpadWatcher.shared.frame(data, count: count, time: timestamp)
    return 0
}

/// Watches the keyboard modifiers (hold ⌃⌥ to show the strip map), ⌃⌥ + scroll wheel, and the
/// mouse (focus follows mouse).
final class InputMonitors {
    static let shared = InputMonitors()

    private var flagsMonitors: [Any] = []
    private var holdTimer: Timer?
    private(set) var holdingStripKeys = false
    var onHoldChanged: ((Bool) -> Void)?

    private var scrollTap: CFMachPort?
    private var scrollSource: CFRunLoopSource?
    private var scrollIdle: Timer?
    private var scrolling = false
    private var scrollVelocity = 0.0
    private var lastScrollTime = 0.0

    private var mouseMonitor: Any?
    private var hoverWork: DispatchWorkItem?
    private var lastHover: WindowID?

    func apply(_ c: Config) {
        if flagsMonitors.isEmpty {
            let handler: (NSEvent) -> Void = { [weak self] e in self?.flagsChanged(e.modifierFlags) }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { flagsMonitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) {
                flagsMonitors.append(l)
            }
        }
        if c.scrollWheelWithModifiers && c.tilingEnabled { installScrollTap() } else { removeScrollTap() }
        if c.focusFollowsMouse && c.tilingEnabled { installMouseMonitor() } else { removeMouseMonitor() }
    }

    private func flagsChanged(_ f: NSEvent.ModifierFlags) {
        let m = f.intersection([.control, .option, .shift, .command])
        let holding = m == [.control, .option]
        if holding && holdTimer == nil && !holdingStripKeys {
            let t = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.holdTimer = nil
                self.holdingStripKeys = true
                self.onHoldChanged?(true)
            }
            RunLoop.main.add(t, forMode: .common)
            holdTimer = t
        } else if !holding {
            holdTimer?.invalidate()
            holdTimer = nil
            if holdingStripKeys {
                holdingStripKeys = false
                onHoldChanged?(false)
            }
        }
    }

    // MARK: ⌃⌥ + scroll wheel

    private func installScrollTap() {
        guard scrollTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = InputMonitors.shared.scrollTap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return InputMonitors.shared.scrollEvent(event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil) else {
            Log.info("Scroll wheel tap unavailable (needs Accessibility)")
            return
        }
        scrollTap = tap
        scrollSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), scrollSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeScrollTap() {
        if let s = scrollSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = scrollTap { CGEvent.tapEnable(tap: t, enable: false) }
        scrollTap = nil
        scrollSource = nil
    }

    /// Returns true to swallow the event.
    private func scrollEvent(_ e: CGEvent) -> Bool {
        let flags = e.flags
        guard flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand) else { return false }
        // Trackpads report momentum and continuous phases; mice report line deltas.
        let continuous = e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        var dx = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        var dy = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if !continuous { dx *= 6; dy *= 6 }
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        guard delta != 0 else { return true }
        let now = CACurrentMediaTime()
        DispatchQueue.main.async {
            let wm = WindowManager.shared
            if !self.scrolling {
                self.scrolling = true
                self.scrollVelocity = 0
                wm.interactiveBegin()
            }
            let dt = max(0.005, now - self.lastScrollTime)
            self.lastScrollTime = now
            self.scrollVelocity = self.scrollVelocity * 0.5 + (delta * 2 / dt) * 0.5
            wm.interactiveScroll(points: delta * 2)
            self.scrollIdle?.invalidate()
            let t = Timer(timeInterval: 0.18, repeats: false) { _ in
                self.scrolling = false
                wm.interactiveEnd(velocityPoints: max(-4000, min(4000, self.scrollVelocity)) * 0.3)
            }
            RunLoop.main.add(t, forMode: .common)
            self.scrollIdle = t
        }
        return true
    }

    // MARK: Focus follows mouse

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.mouseMoved() }
    }

    private func removeMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
    }

    private func mouseMoved() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let wm = WindowManager.shared
        let target = wm.windowsUnderMouseFocusable()
        guard target != lastHover else { return }
        lastHover = target
        hoverWork?.cancel()
        guard let target, target != wm.focusedWindowID else { return }
        let w = DispatchWorkItem { [weak wm] in
            guard let wm, wm.windowsUnderMouseFocusable() == target else { return }
            wm.focus(window: target)
        }
        hoverWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }
}
#endif
