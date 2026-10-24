#if os(macOS)
import AppKit
import QuartzCore
import RibbonCore

/// Identifies one screen: a display plus the Space showing on it.
struct ScreenKey: Hashable, CustomStringConvertible {
    let display: String
    let space: UInt64
    var description: String { "\(display.prefix(8))#\(space)" }
}

final class TrackedWindow {
    let id: WindowID
    let element: AXElement
    let pid: pid_t
    let bundleID: String?
    let appName: String
    var title: String
    /// Floated by the user, an app setting, or because it can't be resized.
    var floating = false
    /// Floated only because its screen was full; it tiles again when there's room.
    var overflowed = false
    /// The screen the window is tiled on; nil while floating, minimised, hidden or on another Space.
    var key: ScreenKey?
    /// The smallest size the app accepts, learned when it refuses to shrink.
    var minSize = Size(w: 0, h: 0)
    /// Last frame we sent (or read after a user change).
    var lastFrame: Rect?
    var lastSetTime: CFTimeInterval = 0
    let openingFrame: Rect
    /// Order Ribbon first saw windows in; newer windows are the first to float when a screen can't fit them.
    let seq: Int
    var fights: [CFTimeInterval] = []
    var repairs: [CFTimeInterval] = []

    init(id: WindowID, element: AXElement, pid: pid_t, bundleID: String?, appName: String, title: String, frame: Rect, seq: Int) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        self.appName = appName; self.title = title; self.openingFrame = frame; self.seq = seq
    }

    var ref: SavedWindow { SavedWindow(id: id, bundleID: bundleID, title: title) }
}

/// Where a window was, so it returns to the same place after being minimised, hidden or floated.
struct DetachedSlot {
    let key: ScreenKey
    let index: Int
}

final class WindowManager {
    static let shared = WindowManager()

    let store = SettingsStore.shared
    var config: Config { store.config }

    var windows: [WindowID: TrackedWindow] = [:]
    var boards: [ScreenKey: Board] = [:]
    /// Tile frames from the last layout of each screen.
    var tileFrames: [ScreenKey: [Rect]] = [:]
    var displays: [Display] = []
    private(set) var isRunning = false
    var focusedWindowID: WindowID?
    /// Windows in the order they were last used, most recent first.
    var recentWindows: [WindowID] = []
    let animator = Animator()

    /// Dim and blur everything but the window in use.
    var noPeek = false
    /// Displays showing one window on a plain background.
    var cleanSpace = Set<String>()
    /// Paused because Stage Manager is on.
    private(set) var pausedForStageManager = false

    var observers: [pid_t: AppObserver] = [:]
    var currentSpaces: [String: Spaces.DisplaySpaces] = [:]
    var detached: [WindowID: DetachedSlot] = [:]
    var drag: DragSession?
    var dragMonitors: [Any] = []
    var dragTimer: Timer?
    /// Set while the end-to-end tests drive a synthetic drag (the mouse button state can't be read back).
    var simulatedDrag = false
    private var enforceWork: [WindowID: DispatchWorkItem] = [:]
    private var session: SessionSnapshot?
    private var saveWork: DispatchWorkItem?
    private var syncWork: DispatchWorkItem?
    private var validateTimer: Timer?
    private var permissionTimer: Timer?
    private var stageTimer: Timer?
    private var workspaceObserversInstalled = false
    var pendingFocus: (wid: WindowID, until: CFTimeInterval)?
    var lastKey: ScreenKey?
    private var nextSeq = 0

    /// UI hooks.
    var layoutListeners: [() -> Void] = []
    var frameListeners: [(WindowID, Rect) -> Void] = []
    var commandListeners: [(Command) -> Void] = []
    var runningListeners: [(Bool) -> Void] = []

    private init() {
        animator.onFrame = { [weak self] wid, f in
            guard let self, let w = self.windows[wid] else { return }
            w.lastFrame = f
            w.lastSetTime = CACurrentMediaTime()
            for l in self.frameListeners { l(wid, f) }
        }
        animator.onSettled = { [weak self] in self?.readBack() }
        store.onChange { [weak self] old, new in self?.configChanged(old, new) }
        startStageManagerWatch()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning, config.tilingEnabled, !pausedForStageManager else { return }
        guard AXPermission.isTrusted else { waitForPermission(); return }
        permissionTimer?.invalidate(); permissionTimer = nil
        isRunning = true
        Log.info("Starting (\(AppInfo.version))")
        if session == nil, config.restoreSession { session = SessionStore.load() }
        installWorkspaceObservers()
        refreshDisplays()
        for app in NSWorkspace.shared.runningApplications { observe(app) }
        arrangeInitial()
        syncFocus()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.validate() }
        RunLoop.main.add(t, forMode: .common)
        validateTimer = t
        runningListeners.forEach { $0(true) }
    }

    /// Stops managing windows. They stay exactly where they are.
    func stop() {
        guard isRunning else { return }
        Log.info("Stopping")
        session = snapshot()
        SessionStore.save(session!)
        animator.cancelAll()
        endDrag()
        validateTimer?.invalidate(); validateTimer = nil
        observers.values.forEach { $0.stop() }
        observers.removeAll()
        windows.removeAll()
        boards.removeAll()
        tileFrames.removeAll()
        detached.removeAll()
        cleanSpace.removeAll()
        isRunning = false
        focusedWindowID = nil
        notifyLayout()
        runningListeners.forEach { $0(false) }
    }

    func restart() {
        stop()
        start()
    }

    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            if AXPermission.isTrusted {
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                self?.start()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        permissionTimer = t
    }

    func setTiling(_ on: Bool) {
        store.config.tilingEnabled = on
    }

    private func configChanged(_ old: Config, _ new: Config) {
        if old.tilingEnabled != new.tilingEnabled {
            if new.tilingEnabled { start() } else { stop() }
            return
        }
        if old.pauseForStageManager != new.pauseForStageManager { checkStageManager() }
        guard isRunning else { return }
        if old.appRules != new.appRules || old.floatFixedSizeWindows != new.floatFixedSizeWindows {
            restart()
            return
        }
        if old.layout != new.layout || old.windowsPerScreen != new.windowsPerScreen || old.spacing != new.spacing
            || old.whenFull != new.whenFull {
            relayoutAll(animated: true)
        }
        notifyLayout()
    }

    /// Stage Manager arranges windows itself, so Ribbon steps aside while it's on.
    private func startStageManagerWatch() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.checkStageManager() }
        RunLoop.main.add(t, forMode: .common)
        stageTimer = t
    }

    static var stageManagerOn: Bool {
        UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
    }

    func checkStageManager() {
        let on = config.pauseForStageManager && WindowManager.stageManagerOn
        guard on != pausedForStageManager else { return }
        pausedForStageManager = on
        Log.info(on ? "Stage Manager is on: pausing" : "Stage Manager is off: resuming")
        if on { stop() } else { start() }
        runningListeners.forEach { $0(isRunning) }
    }

    // MARK: - Apps and windows

    private func installWorkspaceObservers() {
        guard !workspaceObserversInstalled else { return }
        workspaceObserversInstalled = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.isRunning, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.observe(app)
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.isRunning, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.appTerminated(app.processIdentifier)
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.isRunning else { return }
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, self.observers[app.processIdentifier] == nil {
                self.observe(app)
            }
            self.syncFocus()
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.refreshSpaces()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.syncVisibility()
                self.relayoutAll(animated: false)
                self.syncFocus()
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.recoverAfterChange() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.endCleanSpace() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.recoverAfterChange() }
        }
    }

    private func observe(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard isRunning, app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil, !app.isTerminated else { return }
        if config.rule(for: app.bundleIdentifier)?.behavior == .ignore { return }
        let obs = AppObserver(app: app) { [weak self] o, e in self?.handle(o, e) }
        if obs.start() {
            observers[pid] = obs
            for el in obs.app.windows { adopt(el, app: obs) }
            if attempt > 0 { scheduleSync() }
        } else if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.observe(app, attempt: attempt + 1) }
        }
    }

    private func appTerminated(_ pid: pid_t) {
        observers[pid]?.stop()
        observers[pid] = nil
        var touched = Set<ScreenKey>()
        for w in windows.values where w.pid == pid {
            if let k = w.key, var b = boards[k] { b.remove(w.id); boards[k] = b; touched.insert(k) }
            forget(w.id)
        }
        touched.forEach { fillFromOverflow($0); relayout($0) }
        notifyLayout()
    }

    private enum Kind { case tile, float, ignore }

    private func classify(_ el: AXElement, app: AppObserver) -> Kind {
        guard el.role == kAXWindowRole else { return .ignore }
        switch config.rule(for: app.bundleID)?.behavior {
        case .ignore?: return .ignore
        case .float?: return .float
        default: break
        }
        // Dialogs, sheets, panels and pop-ups are never tiled.
        guard let sub = el.subrole, !sub.isEmpty, sub != "AXUnknown" else { return .ignore }
        if sub != kAXStandardWindowSubrole { return .float }
        if el.bool("AXModal") == true { return .float }
        if config.floatFixedSizeWindows {
            if !el.isSettable(kAXSizeAttribute) { return .float }
            if let zoom = el.element(kAXZoomButtonAttribute), !zoom.isEnabled { return .float }
        }
        if let f = el.frame, f.w < 160 || f.h < 110 { return .float }
        return .tile
    }

    /// Starts tracking a window (it isn't tiled until it is visible).
    @discardableResult
    func adopt(_ el: AXElement, app: AppObserver) -> TrackedWindow? {
        guard let wid = el.windowID else { return nil }
        if let w = windows[wid] { return w }
        let kind = classify(el, app: app)
        guard kind != .ignore else { return nil }
        let frame = el.frame ?? Rect(x: 100, y: 100, w: 800, h: 600)
        nextSeq += 1
        let w = TrackedWindow(id: wid, element: el, pid: app.pid, bundleID: app.bundleID, appName: app.name,
                              title: el.title, frame: frame, seq: nextSeq)
        w.floating = kind == .float
        w.lastFrame = frame
        windows[wid] = w
        app.watch(el)
        Log.debug("adopt \(wid) \(app.name) '\(w.title)' \(kind) \(frame)")
        return w
    }

    private func forget(_ wid: WindowID) {
        animator.cancel(wid)
        windows[wid] = nil
        detached[wid] = nil
        enforceWork[wid]?.cancel()
        enforceWork[wid] = nil
        recentWindows.removeAll { $0 == wid }
        if focusedWindowID == wid { focusedWindowID = nil }
        if drag?.wid == wid { endDrag() }
    }

    func tracked(_ el: AXElement, pid: pid_t? = nil) -> TrackedWindow? {
        if let wid = el.windowID, let w = windows[wid] { return w }
        return windows.values.first { (pid == nil || $0.pid == pid) && $0.element == el }
    }

    // MARK: - AX events

    private func handle(_ app: AppObserver, _ e: AppObserver.Event) {
        guard isRunning else { return }
        switch e {
        case .windowCreated(let el):
            adoptCreated(el, app: app, attempt: 0)
        case .focusChanged:
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.pid { syncFocus() }
        case .moved(let el):
            changedExternally(el, resized: false)
        case .resized(let el):
            changedExternally(el, resized: true)
        case .minimized(let el):
            if let w = tracked(el, pid: app.pid) { detach(w) }
        case .deminimized:
            scheduleSync(after: 0.15)
        case .destroyed(let el):
            if let w = tracked(el, pid: app.pid) { windowDestroyed(w) }
        case .titleChanged(let el):
            if let w = tracked(el, pid: app.pid) {
                w.title = el.title
                notifyLayout()
            }
        case .appHidden:
            var touched = Set<ScreenKey>()
            for w in windows.values where w.pid == app.pid {
                if let k = w.key { touched.insert(k) }
                detach(w, relayoutNow: false)
            }
            touched.forEach { relayout($0) }
        case .appShown:
            scheduleSync(after: 0.1)
        }
    }

    private func adoptCreated(_ el: AXElement, app: AppObserver, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.06 : 0.2)) { [weak self] in
            guard let self, self.isRunning else { return }
            if el.subrole == nil, attempt < 4 { self.adoptCreated(el, app: app, attempt: attempt + 1); return }
            if self.adopt(el, app: app) != nil { self.syncVisibility() }
            // Windows that appear slowly get a second look.
            if attempt == 0 { self.scheduleSync(after: 0.6) }
        }
    }

    private func windowDestroyed(_ w: TrackedWindow) {
        let key = w.key
        let pid = w.pid
        let lastFrame = w.lastFrame
        forget(w.id)
        guard let key, var b = boards[key] else { return }
        // A native tab closing reveals its sibling in the same place: it takes over the spot.
        if let lf = lastFrame, let sibling = visibleUnplaced(pid: pid, near: lf) {
            b.replace(w.id, with: sibling.id)
            boards[key] = b
            sibling.key = key
            relayout(key)
            return
        }
        b.remove(w.id)
        boards[key] = b
        fillFromOverflow(key)
        relayout(key)
        notifyLayout()
    }

    func visibleUnplaced(pid: pid_t, near frame: Rect) -> TrackedWindow? {
        let onScreen = WindowServer.all(onScreenOnly: true)
        return windows.values.first { w in
            w.pid == pid && w.key == nil && !w.floating && onScreen[w.id] != nil &&
                (w.element.frame.map { $0.isClose(to: frame, tolerance: 40) } ?? false)
        }
    }

    /// A tiled window moved or resized without us asking: the user dragged it, or the app did.
    private func changedExternally(_ el: AXElement, resized: Bool) {
        guard let wid = el.windowID, let w = windows[wid], let key = w.key, !w.floating else { return }
        if animator.isAnimating(wid) { return }
        guard let actual = el.frame else { return }
        if mouseIsDown, CACurrentMediaTime() - w.lastSetTime > 0.15 {
            if let last = w.lastFrame, actual.isClose(to: last, tolerance: 1), drag?.wid != wid { return }
            userDragged(w, key: key, actual: actual, resized: resized)
            return
        }
        if CACurrentMediaTime() - w.lastSetTime < 0.35 { return }
        if let last = w.lastFrame, actual.isClose(to: last, tolerance: 2) { return }
        if el.isFullScreen {
            detach(w)
            return
        }
        scheduleEnforce(w)
    }

    /// Puts a window back when its app moves it, giving up on apps that keep insisting.
    private func scheduleEnforce(_ w: TrackedWindow) {
        enforceWork[w.id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak w] in
            guard let self, let w, let key = w.key, let actual = w.element.frame else { return }
            let now = CACurrentMediaTime()
            w.fights = w.fights.filter { now - $0 < 10 } + [now]
            if let target = self.targetFrame(for: w.id) {
                if actual.w > target.w + 4 { w.minSize.w = max(w.minSize.w, actual.w) }
                if actual.h > target.h + 4 { w.minSize.h = max(w.minSize.h, actual.h) }
            }
            w.lastFrame = actual
            if w.fights.count > 4 {
                Log.info("\(w.appName) keeps moving its window; leaving it be for now")
                return
            }
            self.animator.mover.invalidate(w.id)
            self.relayout(key)
        }
        enforceWork[w.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// After animations: check every window really is where the layout put it. Apps that refuse to
    /// shrink teach us their minimum size; anything else that's off gets put right (a few times at
    /// most, so an app that insists on its own frame doesn't cause a fight).
    func readBack() {
        struct Miss { let key: ScreenKey; let w: TrackedWindow; let target: Rect }
        func misses() -> [Miss] {
            var out: [Miss] = []
            for (key, b) in boards where isActive(key) {
                for wid in b.windows {
                    guard let w = windows[wid], w.key == key, !animator.isAnimating(wid), drag?.wid != wid,
                          let target = targetFrame(for: wid)?.rounded(), let actual = w.element.frame else { continue }
                    if !actual.isClose(to: target, tolerance: 2) { out.append(Miss(key: key, w: w, target: target)) }
                }
            }
            return out
        }
        let first = misses()
        guard !first.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let suspects = Set(first.map { $0.w.id })
            var touched = Set<ScreenKey>()
            var repaired = false
            let now = CACurrentMediaTime()
            for m in self.misses() where suspects.contains(m.w.id) {
                guard let actual = m.w.element.frame else { continue }
                // Still bigger than asked: that's the app's minimum. Small overshoots (Finder stops at 501pt)
                // only count once a repair has failed, so a window caught mid-resize isn't mistaken for one.
                let retried = !m.w.repairs.filter { now - $0 < 10 }.isEmpty
                let wider = actual.w > m.target.w + 4 || (actual.w > m.target.w + 1 && retried)
                let taller = actual.h > m.target.h + 4 || (actual.h > m.target.h + 1 && retried)
                var learned = false
                if wider, m.w.minSize.w < actual.w - 1 { m.w.minSize.w = actual.w; learned = true }
                if taller, m.w.minSize.h < actual.h - 1 { m.w.minSize.h = actual.h; learned = true }
                if learned {
                    touched.insert(m.key)
                    Log.info("\(m.w.appName) won't go smaller than \(Int(m.w.minSize.w))x\(Int(m.w.minSize.h))")
                    continue
                }
                m.w.repairs = m.w.repairs.filter { now - $0 < 10 }
                guard m.w.repairs.count < 3 else { continue }
                m.w.repairs.append(now)
                repaired = true
                Log.debug("repair \(m.w.id) \(m.w.appName): \(actual) -> \(m.target)")
                m.w.lastFrame = actual
                self.animator.mover.invalidate(m.w.id)
                self.animator.move(m.w.id, element: m.w.element, pid: m.w.pid, from: actual, to: m.target, animated: false, response: 0)
            }
            touched.forEach { self.relayout($0) }
            if repaired {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.readBack() }
            }
        }
    }

    // MARK: - Visibility sync (the safety net for every missed notification)

    func scheduleSync(after delay: Double = 0.05) {
        syncWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.syncVisibility() }
        syncWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    /// Tiles windows that became visible and lets go of ones that vanished from the current Space.
    func syncVisibility() {
        guard isRunning else { return }
        let onScreen = WindowServer.all(onScreenOnly: true)
        var touched = Set<ScreenKey>()
        var hiddenPids = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications where app.isHidden { hiddenPids.insert(app.processIdentifier) }

        // Tiled windows that are no longer on screen: minimised, moved to another Space, or a
        // native tab that went to the background (its sibling takes the spot).
        for w in windows.values {
            guard let key = w.key, isActive(key), onScreen[w.id] == nil, !animator.isAnimating(w.id) else { continue }
            if CACurrentMediaTime() - w.lastSetTime < 0.5 { continue }
            if let sibling = visibleUnplaced(pid: w.pid, near: w.lastFrame ?? w.openingFrame), sibling.id != w.id,
               var b = boards[key] {
                b.replace(w.id, with: sibling.id)
                boards[key] = b
                sibling.key = key
                w.key = nil
                touched.insert(key)
                Log.debug("tab swap \(w.id) -> \(sibling.id)")
                continue
            }
            detach(w, relayoutNow: false)
            touched.insert(key)
        }

        // Visible windows that aren't tiled yet (or sit on a screen for a Space that isn't showing).
        let newcomers = windows.values.filter { w in
            guard !w.floating, onScreen[w.id] != nil, !hiddenPids.contains(w.pid) else { return false }
            if let key = w.key { return !isActive(key) && activeKey(forWindow: w) != nil && activeKey(forWindow: w) != key }
            return true
        }.sorted { $0.seq < $1.seq }

        let focusedNow = osFocusedWindowID()
        for w in newcomers {
            if w.element.isMinimized || w.element.isFullScreen { continue }
            if let old = w.key, var b = boards[old] {
                b.remove(w.id); boards[old] = b; w.key = nil
            }
            if let k = attach(w, activate: w.id == focusedNow || focusedNow == nil) { touched.insert(k) }
        }
        for k in touched { fillFromOverflow(k); relayout(k) }
        if !touched.isEmpty { notifyLayout() }
    }

    /// Tiles a window on the screen it's on. Returns the screen.
    @discardableResult
    func attach(_ w: TrackedWindow, activate: Bool, to target: ScreenKey? = nil) -> ScreenKey? {
        guard w.key == nil, !w.floating else { return nil }
        let slot = detached.removeValue(forKey: w.id)
        guard let key = target ?? (slot.map { isActive($0.key) ? $0.key : nil } ?? nil) ?? activeKey(forWindow: w),
              let d = display(uuid: key.display) else { return nil }
        var b = boards[key] ?? Board()
        let cap = capacity(key, d)
        let stack = config.whenFull == .stack
        let result: AddResult
        if let slot, slot.key == key {
            result = b.restore(w.id, at: slot.index, capacity: cap, stackWhenFull: stack)
        } else {
            result = b.add(w.id, capacity: cap, stackWhenFull: stack, activate: activate)
        }
        if result == .full {
            overflow(w, on: d)
            return nil
        }
        boards[key] = b
        w.key = key
        w.overflowed = false
        Log.debug("attach \(w.id) \(w.appName) -> \(key) (\(result))")
        return key
    }

    /// A full screen with "float in the middle": the window moves to the centre once and waits for room.
    private func overflow(_ w: TrackedWindow, on d: Display) {
        guard !w.overflowed else { return }
        w.overflowed = true
        w.floating = true
        let f = centered(w, on: d)
        animator.move(w.id, element: w.element, pid: w.pid, from: w.element.frame, to: f, animated: config.animate, response: config.animationResponse)
        UIHub.shared.notice("This Space is full", symbol: "rectangle.stack.badge.plus", on: d)
        Log.info("\(w.appName) floats: the screen is full")
    }

    /// When tiles free up, the windows that waited longest take them.
    func fillFromOverflow(_ key: ScreenKey) {
        guard let d = display(uuid: key.display) else { return }
        let onScreen = WindowServer.all(onScreenOnly: true)
        var waiting = windows.values.filter { $0.overflowed && onScreen[$0.id] != nil && activeKey(forWindow: $0) == key }
            .sorted { $0.seq < $1.seq }
        while !waiting.isEmpty, (boards[key]?.tiles.count ?? 0) < capacity(key, d) {
            let w = waiting.removeFirst()
            w.floating = false
            w.overflowed = false
            attach(w, activate: false, to: key)
        }
    }

    func detach(_ w: TrackedWindow, relayoutNow: Bool = true) {
        guard let key = w.key, var b = boards[key], let i = b.tileIndex(of: w.id) else { return }
        detached[w.id] = DetachedSlot(key: key, index: i)
        b.remove(w.id)
        boards[key] = b
        w.key = nil
        animator.cancel(w.id)
        if relayoutNow {
            fillFromOverflow(key)
            relayout(key)
        }
    }

    /// The window's own size, in the middle of the screen.
    func centered(_ w: TrackedWindow, on d: Display) -> Rect {
        let base = w.openingFrame
        let size = Size(w: min(max(base.w, 480), d.visible.w * 0.7), h: min(max(base.h, 360), d.visible.h * 0.75))
        return Rect(x: d.visible.midX - size.w / 2, y: d.visible.midY - size.h / 2, w: size.w, h: size.h).rounded()
    }

    private func validate() {
        guard isRunning else { return }
        let all = WindowServer.all()
        var touched = Set<ScreenKey>()
        for w in Array(windows.values) where all[w.id] == nil {
            if let k = w.key, var b = boards[k] { b.remove(w.id); boards[k] = b; touched.insert(k) }
            forget(w.id)
        }
        touched.forEach { fillFromOverflow($0); relayout($0) }
        // Pick up windows of apps whose creation notification we missed.
        if let front = NSWorkspace.shared.frontmostApplication, let obs = observers[front.processIdentifier] {
            for el in obs.app.windows where el.windowID.map({ windows[$0] == nil }) ?? false { adopt(el, app: obs) }
        }
        syncVisibility()
    }

    // MARK: - Displays and Spaces

    func refreshDisplays() {
        displays = Displays.current()
        refreshSpaces()
    }

    func refreshSpaces() {
        currentSpaces = Spaces.snapshot()
    }

    func display(uuid: String) -> Display? { displays.first { $0.uuid == uuid } }

    func display(at p: Point) -> Display? {
        displays.first { $0.frame.contains(p) }
    }

    func display(for r: Rect) -> Display? {
        let best = displays.max { r.intersectionArea($0.frame) < r.intersectionArea($1.frame) }
        if let best, r.intersectionArea(best.frame) > 0 { return best }
        return displays.min {
            hypot($0.frame.midX - r.midX, $0.frame.midY - r.midY) < hypot($1.frame.midX - r.midX, $1.frame.midY - r.midY)
        }
    }

    func activeKey(for d: Display) -> ScreenKey? {
        let sp = Spaces.spaces(for: currentSpaces, displayUUID: d.uuid)
        if sp?.currentIsFullscreen == true { return nil }
        return ScreenKey(display: d.uuid, space: sp?.current ?? 0)
    }

    func activeKey(forWindow w: TrackedWindow) -> ScreenKey? {
        guard let f = w.element.frame ?? w.lastFrame, let d = display(for: f) else { return nil }
        return activeKey(for: d)
    }

    func isActive(_ key: ScreenKey) -> Bool {
        guard let d = display(uuid: key.display) else { return false }
        return activeKey(for: d) == key
    }

    var activeKeys: [ScreenKey] { displays.compactMap { activeKey(for: $0) } }

    func spaceIndex(_ key: ScreenKey) -> Int {
        Spaces.spaces(for: currentSpaces, displayUUID: key.display)?.all.firstIndex(of: key.space) ?? 0
    }

    private func recoverAfterChange() {
        guard isRunning else { return }
        let old = Set(displays.map(\.uuid))
        refreshDisplays()
        let now = Set(displays.map(\.uuid))
        cleanSpace = cleanSpace.intersection(now)
        if old != now {
            Log.info("Displays changed: \(displays.map(\.name))")
            // Windows on displays that went away join the main display.
            let mainKey = (displays.first { $0.isMain } ?? displays.first).flatMap { activeKey(for: $0) }
            for (key, b) in boards where !now.contains(key.display) {
                for wid in b.windows {
                    guard let w = windows[wid] else { continue }
                    w.key = nil
                    detached[wid] = nil
                    if let mk = mainKey { attach(w, activate: false, to: mk) }
                }
                boards[key] = nil
                tileFrames[key] = nil
            }
        }
        syncVisibility()
        relayoutAll(animated: false)
        syncFocus()
    }

    // MARK: - Initial arrangement and session restore

    private func arrangeInitial() {
        let onScreen = WindowServer.all(onScreenOnly: true)
        var groups: [ScreenKey: [TrackedWindow]] = [:]
        for w in windows.values where !w.floating && onScreen[w.id] != nil && !w.element.isMinimized && !w.element.isFullScreen {
            if let k = activeKey(forWindow: w) { groups[k, default: []].append(w) }
        }
        let focusedNow = osFocusedWindowID()
        for (key, list) in groups {
            var b = Board()
            var remaining = list
            if config.restoreSession, let session,
               let snap = SessionRestore.snapshot(in: session, displayUUID: key.display, spaceID: key.space, spaceIndex: spaceIndex(key)) {
                var used = Set<WindowID>()
                b = SessionRestore.restore(snap, live: list.map(\.ref), used: &used)
                remaining = list.filter { !used.contains($0.id) }
                if !used.isEmpty { Log.info("Restored \(used.count) windows on \(key)") }
            }
            boards[key] = b
            for wid in b.windows { windows[wid]?.key = key }
            // The rest go in the order they sit on screen: left to right, top to bottom.
            let ordered = remaining.sorted {
                let a = $0.element.frame ?? $0.openingFrame, c = $1.element.frame ?? $1.openingFrame
                return (a.x, a.y) < (c.x, c.y)
            }
            for w in ordered { attach(w, activate: false, to: key) }
            if let f = focusedNow, var bb = boards[key], bb.contains(f) { bb.setActive(f); bb.show(f); boards[key] = bb }
        }
        relayoutAll(animated: true)
    }

    func snapshot() -> SessionSnapshot {
        var all = boards
        // Screens without windows still remember their window count, layout and sizes.
        if let old = session {
            for s in old.boards {
                let key = ScreenKey(display: s.displayUUID, space: s.spaceID)
                if all[key] == nil, s.layout != nil || s.capacity != nil || !s.splits.isDefault {
                    var b = Board()
                    b.layout = s.layout; b.capacity = s.capacity; b.splits = s.splits
                    all[key] = b
                }
            }
        }
        let snaps = all.filter { !$0.value.isEmpty || $0.value.layout != nil || $0.value.capacity != nil || !$0.value.splits.isDefault }
            .map { key, b in
                BoardSnapshot(displayUUID: key.display, spaceID: key.space, spaceIndex: spaceIndex(key), board: b) { self.windows[$0]?.ref }
            }
        return SessionSnapshot(boards: snaps)
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            SessionStore.save(self.snapshot())
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    // MARK: - Layout

    func area(for d: Display) -> Rect { d.visible.insetBy(config.spacing) }

    func layoutKind(_ key: ScreenKey) -> LayoutKind { boards[key]?.layout ?? config.layout }

    func arrangement(_ key: ScreenKey, _ d: Display) -> Arrangement {
        TileLayout.arrangement(layoutKind(key), area: area(for: d))
    }

    func capacity(_ key: ScreenKey, _ d: Display) -> Int {
        TileLayout.capacity(requested: boards[key]?.capacity ?? config.windowsPerScreen, arrangement(key, d), area: area(for: d))
    }

    /// Where a tiled window should be right now.
    func targetFrame(for wid: WindowID) -> Rect? {
        guard let w = windows[wid], let key = w.key, let b = boards[key], let i = b.tileIndex(of: wid),
              let frames = tileFrames[key], frames.indices.contains(i), let d = display(uuid: key.display) else { return nil }
        if b.zoomed == wid { return area(for: d) }
        return frames[i]
    }

    private func mins(_ b: Board) -> [Size] {
        b.tiles.map { t in
            t.windows.reduce(Size(w: 0, h: 0)) { acc, wid in
                let m = windows[wid]?.minSize ?? Size(w: 0, h: 0)
                return Size(w: max(acc.w, m.w), h: max(acc.h, m.h))
            }
        }
    }

    func relayoutAll(animated: Bool = true) {
        for key in Set(boards.keys).union(activeKeys) where isActive(key) { relayout(key, animated: animated) }
    }

    /// Places every window on a screen. `except` skips the window the user is dragging.
    func relayout(_ key: ScreenKey, animated: Bool = true, except: WindowID? = nil) {
        guard isRunning, var b = boards[key], let d = display(uuid: key.display), isActive(key) else { return }
        let A = area(for: d)
        let arr = arrangement(key, d)
        b.fit(capacity: capacity(key, d))
        var m = mins(b)
        var frames = TileLayout.frames(count: b.tiles.count, arr, area: A, gap: config.spacing, splits: b.splits, mins: m)
        // A window that can't fit floats in the middle, newest first.
        var guardCount = 0
        while !TileLayout.fits(frames, mins: m), guardCount < 4 {
            guardCount += 1
            let misfits = frames.indices.filter { frames[$0].w < m[$0].w - 1 || frames[$0].h < m[$0].h - 1 }
            let candidates = misfits.flatMap { b.tiles[$0].windows }.compactMap { windows[$0] }
            guard let w = candidates.max(by: { $0.seq < $1.seq }) else { break }
            b.remove(w.id)
            w.key = nil
            w.floating = true
            w.overflowed = true
            animator.move(w.id, element: w.element, pid: w.pid, from: w.lastFrame, to: centered(w, on: d), animated: config.animate,
                          response: config.animationResponse)
            Log.info("\(w.appName) can't fit next to the others: floating it")
            m = mins(b)
            frames = TileLayout.frames(count: b.tiles.count, arr, area: A, gap: config.spacing, splits: b.splits, mins: m)
        }
        boards[key] = b
        tileFrames[key] = frames
        for (i, t) in b.tiles.enumerated() {
            for wid in t.windows {
                guard wid != except, let w = windows[wid] else { continue }
                let f = (b.zoomed == wid ? A : frames[i]).rounded()
                if !animator.isAnimating(w.id), let lf = w.lastFrame, lf.isClose(to: f, tolerance: 0.5),
                   CACurrentMediaTime() - w.lastSetTime < 5 || w.element.frame.map({ $0.isClose(to: f, tolerance: 1) }) == true {
                    continue
                }
                // Windows waiting in a stack jump straight there; the ones you can see glide.
                let glide = animated && config.animate && t.showing == wid
                animator.move(w.id, element: w.element, pid: w.pid, from: w.lastFrame ?? w.element.frame, to: f,
                              animated: glide, response: config.animationResponse)
            }
        }
        animator.kick()
        if !animated || !config.animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.readBack() }
        }
        scheduleSave()
        notifyLayout()
    }

    func notifyLayout() { layoutListeners.forEach { $0() } }

    // MARK: - Focus

    func osFocusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication, let obs = observers[app.processIdentifier] else { return nil }
        return obs.app.focusedWindow?.windowID
    }

    func syncFocus() {
        guard isRunning else { return }
        guard let app = NSWorkspace.shared.frontmostApplication, let obs = observers[app.processIdentifier],
              let el = obs.app.focusedWindow, let wid = el.windowID else {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() { focusedWindowID = nil }
            notifyLayout()
            return
        }
        if let p = pendingFocus {
            if CACurrentMediaTime() < p.until && p.wid != wid { return }
            pendingFocus = nil
        }
        let w = windows[wid] ?? adopt(el, app: obs)
        focusedWindowID = wid
        recentWindows.removeAll { $0 == wid }
        recentWindows.insert(wid, at: 0)
        if recentWindows.count > 64 { recentWindows.removeLast() }
        guard let w else { notifyLayout(); return }
        if w.key == nil && !w.floating { syncVisibility() }
        if let key = w.key, var b = boards[key] {
            lastKey = key
            var changed = false
            if b.active != wid { b.setActive(wid) }
            // Brought forward with ⌘-Tab, the Dock or a click: it's now the one showing in its stack.
            if b.show(wid) { changed = true }
            // Clean Space follows the window in use; focus mode ends when you switch away.
            if cleanSpace.contains(key.display) {
                if b.zoomed != wid { b.zoomed = wid; changed = true }
            } else if let z = b.zoomed, z != wid {
                b.zoomed = nil
                changed = true
            }
            boards[key] = b
            if changed { relayout(key) }
        }
        notifyLayout()
    }

    func focusOS(_ wid: WindowID) {
        guard let w = windows[wid] else { return }
        pendingFocus = (wid, CACurrentMediaTime() + 0.6)
        focusedWindowID = wid
        recentWindows.removeAll { $0 == wid }
        recentWindows.insert(wid, at: 0)
        let appEl = AXElement.app(w.pid)
        appEl.set(kAXFrontmostAttribute, true)
        w.element.set(kAXMainAttribute, true)
        w.element.perform(kAXRaiseAction)
        if let app = NSRunningApplication(processIdentifier: w.pid), !app.isActive {
            app.activate(options: [])
        }
        if let key = w.key, var b = boards[key] {
            b.setActive(wid)
            if b.show(wid) { boards[key] = b; relayout(key) } else { boards[key] = b }
        }
        notifyLayout()
    }

    func focus(window wid: WindowID) {
        guard let w = windows[wid] else { return }
        if w.element.isMinimized { w.element.set(kAXMinimizedAttribute, false) }
        focusOS(wid)
    }

    /// The screen commands act on: the window in use's, else the one under the pointer.
    func commandKey() -> ScreenKey? {
        if let f = focusedWindowID, let k = windows[f]?.key, isActive(k) { return k }
        if let d = display(at: Displays.mouseLocation), let k = activeKey(for: d) { return k }
        if let k = lastKey, isActive(k) { return k }
        return activeKeys.first
    }

    /// The tiled window under the pointer, if it's showing.
    func tiledWindow(at p: Point) -> WindowID? {
        for (key, b) in boards where isActive(key) {
            guard let frames = tileFrames[key] else { continue }
            if let z = b.zoomed, let d = display(uuid: key.display), area(for: d).contains(p) { return z }
            for (i, f) in frames.enumerated() where f.contains(p) && b.tiles.indices.contains(i) { return b.tiles[i].showing }
        }
        return nil
    }
}
#endif
