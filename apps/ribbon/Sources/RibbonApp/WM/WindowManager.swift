#if os(macOS)
import AppKit
import QuartzCore
import RibbonCore

/// Identifies one strip: a display plus the Space showing on it.
struct StripKey: Hashable, CustomStringConvertible {
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
    var floating = false
    /// Strip the window is in; nil while floating, minimised, hidden or on another Space.
    var key: StripKey?
    var constraints = WindowConstraints()
    /// Last frame we sent (or read after a user change).
    var lastFrame: Rect?
    var lastSetTime: CFTimeInterval = 0
    let openingFrame: Rect
    var fights: [CFTimeInterval] = []
    var repairs: [CFTimeInterval] = []

    init(id: WindowID, element: AXElement, pid: pid_t, bundleID: String?, appName: String, title: String, frame: Rect) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        self.appName = appName; self.title = title; self.openingFrame = frame
        constraints.originalHeight = frame.h
    }

    var ref: SavedWindow { SavedWindow(id: id, bundleID: bundleID, title: title) }
}

/// Remembers where a window was so it returns to the same place after being minimised or hidden.
private struct DetachedSlot {
    let key: StripKey
    let index: Int
    let width: Double
    let leftNeighbor: WindowID?
}

final class WindowManager {
    static let shared = WindowManager()

    private let store = SettingsStore.shared
    var config: Config { store.config }

    private(set) var windows: [WindowID: TrackedWindow] = [:]
    private(set) var strips: [StripKey: Strip] = [:]
    private(set) var layouts: [StripKey: LayoutResult] = [:]
    private(set) var displays: [Display] = []
    private(set) var isRunning = false
    private(set) var focusedWindowID: WindowID?
    let animator = Animator()

    private var observers: [pid_t: AppObserver] = [:]
    private var currentSpaces: [String: Spaces.DisplaySpaces] = [:]
    private var detached: [WindowID: DetachedSlot] = [:]
    private var adjusting = Set<WindowID>()
    private var mouseUpMonitor: Any?
    private var enforceWork: [WindowID: DispatchWorkItem] = [:]
    private var session: SessionSnapshot?
    private var saveWork: DispatchWorkItem?
    private var syncWork: DispatchWorkItem?
    private var validateTimer: Timer?
    private var permissionTimer: Timer?
    private var workspaceObserversInstalled = false
    private var pendingFocus: (wid: WindowID, until: CFTimeInterval)?
    private var lastKey: StripKey?
    private var swipeKey: StripKey?
    private var swipeRaw: Double = 0

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
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard config.tilingEnabled else { return }
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

    /// Stops managing windows, puts parked windows back on screen and keeps the layout for later.
    func stop(releaseWindows: Bool = true) {
        guard isRunning else { return }
        Log.info("Stopping")
        session = snapshot()
        SessionStore.save(session!)
        animator.cancelAll()
        if releaseWindows { releaseParked() }
        validateTimer?.invalidate(); validateTimer = nil
        observers.values.forEach { $0.stop() }
        observers.removeAll()
        windows.removeAll()
        strips.removeAll()
        layouts.removeAll()
        detached.removeAll()
        isRunning = false
        focusedWindowID = nil
        notifyLayout()
        runningListeners.forEach { $0(false) }
    }

    func restart() {
        stop(releaseWindows: false)
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
        guard isRunning else { return }
        if old.appRules != new.appRules || old.floatFixedSizeWindows != new.floatFixedSizeWindows ||
            old.excludedDisplays != new.excludedDisplays {
            restart()
            return
        }
        let layoutKeys: [PartialKeyPath<Config>] = [\.innerGap, \.outerGap, \.centerMode, \.sparse, \.keepOriginalHeight, \.tabBarHeight]
        if layoutKeys.contains(where: { !isEqual(old[keyPath: $0], new[keyPath: $0]) }) {
            relayoutAll(animated: true)
        }
        notifyLayout()
    }

    private func isEqual(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? Double, let b = b as? Double { return a == b }
        if let a = a as? Bool, let b = b as? Bool { return a == b }
        if let a = a as? CenterMode, let b = b as? CenterMode { return a == b }
        if let a = a as? SparseAlignment, let b = b as? SparseAlignment { return a == b }
        return false
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
        var touched = Set<StripKey>()
        for w in windows.values where w.pid == pid {
            if let k = w.key, var s = strips[k] { s.remove(w.id); strips[k] = s; touched.insert(k) }
            forget(w.id)
        }
        touched.forEach { relayout($0) }
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
        guard let sub = el.subrole, !sub.isEmpty, sub != "AXUnknown" else { return .ignore }
        if sub != kAXStandardWindowSubrole { return .float }
        if config.floatFixedSizeWindows {
            if !el.isSettable(kAXSizeAttribute) { return .float }
            if let zoom = el.element(kAXZoomButtonAttribute), !zoom.isEnabled { return .float }
        }
        if let f = el.frame, f.w < 160 || f.h < 110 { return .float }
        return .tile
    }

    /// Starts tracking a window (it isn't placed in a strip until it is visible).
    @discardableResult
    private func adopt(_ el: AXElement, app: AppObserver) -> TrackedWindow? {
        guard let wid = el.windowID else { return nil }
        if let w = windows[wid] { return w }
        let kind = classify(el, app: app)
        guard kind != .ignore else { return nil }
        let frame = el.frame ?? Rect(x: 100, y: 100, w: 800, h: 600)
        let w = TrackedWindow(id: wid, element: el, pid: app.pid, bundleID: app.bundleID, appName: app.name,
                              title: el.title, frame: frame)
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
        adjusting.remove(wid)
        enforceWork[wid]?.cancel()
        enforceWork[wid] = nil
        if focusedWindowID == wid { focusedWindowID = nil }
    }

    private func tracked(_ el: AXElement, pid: pid_t? = nil) -> TrackedWindow? {
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
            changedExternally(el)
        case .resized(let el):
            changedExternally(el)
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
            for w in windows.values where w.pid == app.pid && w.key != nil { detach(w, relayoutNow: false) }
            relayoutAll(animated: true)
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
        let wasFocused = focusedWindowID == w.id
        forget(w.id)
        guard let key, var s = strips[key] else { return }
        // A native tab closing reveals its sibling at the same place: swap it in.
        if let lf = lastFrame, let sibling = visibleUnplaced(pid: pid, near: lf) {
            s.replace(w.id, with: sibling.id)
            strips[key] = s
            sibling.key = key
            relayout(key, reveal: false)
            return
        }
        s.remove(w.id)
        strips[key] = s
        relayout(key, reveal: true)
        if wasFocused, let f = s.focusedWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            // The app usually focuses another of its own windows; only step in if it doesn't.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.focusedWindowID == nil else { return }
                self.focusOS(f)
            }
        }
        notifyLayout()
    }

    private func visibleUnplaced(pid: pid_t, near frame: Rect) -> TrackedWindow? {
        let onScreen = WindowServer.all(onScreenOnly: true)
        return windows.values.first { w in
            w.pid == pid && w.key == nil && !w.floating && onScreen[w.id] != nil &&
                (w.element.frame.map { $0.isClose(to: frame, tolerance: 40) } ?? false)
        }
    }

    /// A tiled window moved or resized without us asking: the user dragged it, or the app did.
    private func changedExternally(_ el: AXElement) {
        guard let wid = el.windowID, let w = windows[wid], let key = w.key, !w.floating else { return }
        if animator.isAnimating(wid) { return }
        if CACurrentMediaTime() - w.lastSetTime < 0.35 { return }
        guard let actual = el.frame else { return }
        if let last = w.lastFrame, actual.isClose(to: last, tolerance: 2) { return }
        if el.isFullScreen {
            detach(w)
            return
        }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            adjusting.insert(wid)
            installMouseUpMonitor()
            return
        }
        scheduleEnforce(w, key: key)
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.finishAdjusting() }
        }
    }

    private func finishAdjusting() {
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        let ids = adjusting
        adjusting.removeAll()
        for wid in ids { if let w = windows[wid] { userAdjusted(w) } }
    }

    /// After a drag ends: a resize changes the column, a move reorders or changes display.
    private func userAdjusted(_ w: TrackedWindow) {
        guard let key = w.key, var s = strips[key], let r = layouts[key], let pl = r.placement(for: w.id),
              let actual = w.element.frame, let d = display(uuid: key.display) else { return }
        let target = pl.frame
        w.lastFrame = actual
        animator.mover.invalidate(w.id)
        let dw = abs(actual.w - target.w), dh = abs(actual.h - target.h)
        if dw > 4 || dh > 4 {
            let working = d.visible.w - 2 * config.outerGap
            if dw > 4 {
                s.setWidth(Layout.fraction(forPixelWidth: actual.w, working: working, gap: config.innerGap), column: pl.column)
                s.columns[pl.column].savedWidth = nil
                w.constraints.minWidth = nil
            }
            let n = Double(s.columns[pl.column].windows.count)
            if n > 1, dh > 4, s.columns[pl.column].mode == .stacked {
                let avail = d.visible.h - 2 * config.outerGap - (n - 1) * config.innerGap
                s.setWeight(window: w.id, share: actual.h / avail)
            } else if n == 1, dh > 4 {
                w.constraints.originalHeight = actual.h
            }
            strips[key] = s
            Log.info("User resized \(w.appName) to \(Int(actual.w))x\(Int(actual.h))")
            relayout(key, reveal: true)
            return
        }
        let mouse = Displays.mouseLocation
        if let dd = display(at: mouse), dd.uuid != key.display, let newKey = activeKey(for: dd) {
            let width = s.columns[pl.column].width
            s.remove(w.id)
            strips[key] = s
            var t = strips[newKey] ?? Strip()
            let idx = layouts[newKey].map { Layout.insertionIndex(atScreenX: mouse.x, in: $0, excluding: nil) } ?? t.columns.count
            t.insert(w.id, width: width, at: .index(idx), focus: true)
            strips[newKey] = t
            w.key = newKey
            Log.info("Dragged \(w.appName) to display \(dd.name)")
            relayout(key)
            relayout(newKey)
            return
        }
        let idx = Layout.insertionIndex(atScreenX: mouse.x, in: r, excluding: pl.column)
        if s.columns[pl.column].windows.count > 1 {
            s.focus(window: w.id)
            s.expel(to: mouse.x < r.columnRects[pl.column].midX ? .left : .right)
        } else {
            s.moveColumn(from: pl.column, to: idx)
        }
        s.focus(window: w.id)
        strips[key] = s
        relayout(key, reveal: true)
    }

    /// Puts a window back when its app moves it, giving up on apps that keep insisting.
    private func scheduleEnforce(_ w: TrackedWindow, key: StripKey) {
        enforceWork[w.id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak w] in
            guard let self, let w, let key = w.key, let actual = w.element.frame else { return }
            let now = CACurrentMediaTime()
            w.fights = w.fights.filter { now - $0 < 10 } + [now]
            if let target = self.layouts[key]?.placement(for: w.id)?.frame, actual.w > target.w + 4,
               self.layouts[key]?.placement(for: w.id)?.visibility != .hidden(.left),
               self.layouts[key]?.placement(for: w.id)?.visibility != .hidden(.right) {
                w.constraints.minWidth = actual.w
            }
            w.lastFrame = actual
            if w.fights.count > 4 {
                Log.info("\(w.appName) keeps moving its window; leaving it be for now")
                return
            }
            self.animator.mover.invalidate(w.id)
            self.relayout(key, reveal: false)
        }
        enforceWork[w.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// After animations: check that every window really is where the layout put it. Apps that
    /// refuse to shrink teach us their minimum width; anything else that's off gets put right
    /// (a few times at most, so an app that insists on its own frame doesn't cause a fight).
    private func readBack() {
        struct Miss { let key: StripKey; let w: TrackedWindow; let target: Rect; let onScreen: Bool }
        func misses() -> [Miss] {
            var out: [Miss] = []
            for (key, r) in layouts where isActive(key) {
                guard let d = display(uuid: key.display) else { continue }
                let others = displays.filter { $0.uuid != d.uuid }.map(\.frame)
                for pl in r.placements {
                    guard let w = windows[pl.window], w.key == key, !animator.isAnimating(w.id), let actual = w.element.frame else { continue }
                    var target = pl.frame.rounded()
                    let onScreen = pl.visibility.isOnScreen
                    if case .hidden(let side) = pl.visibility {
                        target = Parking.frame(size: target.size, side: side, screen: d.frame, others: others, y: target.y)
                    }
                    let sizeOK = abs(actual.w - target.w) <= 2 && abs(actual.h - target.h) <= 2
                    let posOK = abs(actual.x - target.x) <= 2 && abs(actual.y - target.y) <= 2
                    if !sizeOK || (onScreen && !posOK) { out.append(Miss(key: key, w: w, target: target, onScreen: onScreen)) }
                }
            }
            return out
        }
        let first = misses()
        guard !first.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let suspects = Set(first.map { $0.w.id })
            var touched = Set<StripKey>()
            var repaired = false
            let now = CACurrentMediaTime()
            for m in misses() where suspects.contains(m.w.id) {
                guard let actual = m.w.element.frame else { continue }
                if m.onScreen, actual.w > m.target.w + 4, (m.w.constraints.minWidth ?? 0) < actual.w - 1 {
                    m.w.constraints.minWidth = actual.w
                    touched.insert(m.key)
                    Log.info("\(m.w.appName) won't go narrower than \(Int(actual.w))pt")
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
            touched.forEach { self.relayout($0, reveal: true) }
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

    /// Places windows that became visible and removes ones that vanished from the current Space.
    func syncVisibility() {
        guard isRunning else { return }
        let onScreen = WindowServer.all(onScreenOnly: true)
        var touched = Set<StripKey>()
        var hiddenPids = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications where app.isHidden { hiddenPids.insert(app.processIdentifier) }

        // Windows in an active strip that are no longer on screen: minimised, moved to another
        // Space, or a native tab that went to the background.
        for w in windows.values {
            guard let key = w.key, isActive(key), onScreen[w.id] == nil, !animator.isAnimating(w.id) else { continue }
            if CACurrentMediaTime() - w.lastSetTime < 0.5 { continue }
            if let sibling = visibleUnplaced(pid: w.pid, near: w.lastFrame ?? w.openingFrame), sibling.id != w.id,
               var s = strips[key] {
                s.replace(w.id, with: sibling.id)
                strips[key] = s
                sibling.key = key
                w.key = nil
                touched.insert(key)
                Log.debug("tab swap \(w.id) -> \(sibling.id)")
                continue
            }
            detach(w, relayoutNow: false)
            touched.insert(key)
        }

        // Visible windows that aren't placed yet (or sit in a strip for a Space that isn't showing).
        let newcomers = windows.values.filter { w in
            guard !w.floating, onScreen[w.id] != nil, !hiddenPids.contains(w.pid) else { return false }
            if let key = w.key { return !isActive(key) && activeKey(forWindow: w) != nil && activeKey(forWindow: w) != key }
            return true
        }.sorted { ($0.element.frame?.x ?? 0) < ($1.element.frame?.x ?? 0) }

        let focusedNow = osFocusedWindowID()
        for w in newcomers {
            if w.element.isMinimized || w.element.isFullScreen { continue }
            if let old = w.key, var s = strips[old] {
                s.remove(w.id); strips[old] = s; w.key = nil
            }
            if let k = attach(w, focus: w.id == focusedNow) { touched.insert(k) }
        }
        for k in touched { relayout(k, reveal: newcomers.contains { $0.id == focusedNow }) }
        if !touched.isEmpty { notifyLayout() }
    }

    /// Adds a window to the strip of the display it is on. Returns the strip key.
    @discardableResult
    private func attach(_ w: TrackedWindow, focus: Bool) -> StripKey? {
        guard w.key == nil, !w.floating else { return nil }
        if let slot = detached[w.id], isActive(slot.key), var s = strips[slot.key] {
            detached[w.id] = nil
            var idx = slot.index
            if let n = slot.leftNeighbor, let (c, _) = s.locate(n) { idx = c + 1 }
            s.insert(w.id, width: slot.width, at: .index(idx), focus: focus)
            strips[slot.key] = s
            w.key = slot.key
            return slot.key
        }
        detached[w.id] = nil
        guard let key = activeKey(forWindow: w), let d = display(uuid: key.display) else { return nil }
        var s = strips[key] ?? Strip()
        s.insert(w.id, width: openingWidth(for: w, on: d), at: config.newWindowPlacement == .end ? .end : .afterFocused, focus: focus)
        strips[key] = s
        w.key = key
        Log.debug("attach \(w.id) \(w.appName) -> \(key)")
        return key
    }

    private func detach(_ w: TrackedWindow, relayoutNow: Bool = true) {
        guard let key = w.key, var s = strips[key], let (c, _) = s.locate(w.id) else { return }
        let left = c > 0 ? s.columns[c - 1].activeWindow : nil
        detached[w.id] = DetachedSlot(key: key, index: c, width: s.columns[c].width, leftNeighbor: left)
        s.remove(w.id)
        strips[key] = s
        w.key = nil
        animator.cancel(w.id)
        if relayoutNow { relayout(key, reveal: true) }
    }

    private func openingWidth(for w: TrackedWindow, on d: Display) -> Double {
        if let rw = config.rule(for: w.bundleID)?.width { return rw }
        if config.useOwnWidth {
            return Layout.fraction(forPixelWidth: w.openingFrame.w, working: d.visible.w - 2 * config.outerGap, gap: config.innerGap)
        }
        return config.defaultWidth
    }

    private func validate() {
        guard isRunning else { return }
        let all = WindowServer.all()
        var touched = Set<StripKey>()
        for w in Array(windows.values) where all[w.id] == nil {
            if let k = w.key, var s = strips[k] { s.remove(w.id); strips[k] = s; touched.insert(k) }
            forget(w.id)
        }
        touched.forEach { relayout($0) }
        // Pick up windows of apps whose creation notification we missed.
        if let front = NSWorkspace.shared.frontmostApplication, let obs = observers[front.processIdentifier] {
            for el in obs.app.windows where el.windowID.map({ windows[$0] == nil }) ?? false { adopt(el, app: obs) }
        }
        syncVisibility()
    }

    // MARK: - Displays and Spaces

    private func refreshDisplays() {
        displays = Displays.current()
        refreshSpaces()
    }

    private func refreshSpaces() {
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

    func activeKey(for d: Display) -> StripKey? {
        if config.excludedDisplays.contains(d.uuid) { return nil }
        let sp = Spaces.spaces(for: currentSpaces, displayUUID: d.uuid)
        if sp?.currentIsFullscreen == true { return nil }
        return StripKey(display: d.uuid, space: sp?.current ?? 0)
    }

    private func activeKey(forWindow w: TrackedWindow) -> StripKey? {
        guard let f = w.element.frame ?? w.lastFrame, let d = display(for: f) else { return nil }
        return activeKey(for: d)
    }

    func isActive(_ key: StripKey) -> Bool {
        guard let d = display(uuid: key.display) else { return false }
        return activeKey(for: d) == key
    }

    var activeKeys: [StripKey] { displays.compactMap { activeKey(for: $0) } }

    private func spaceIndex(_ key: StripKey) -> Int {
        Spaces.spaces(for: currentSpaces, displayUUID: key.display)?.all.firstIndex(of: key.space) ?? 0
    }

    private func recoverAfterChange() {
        guard isRunning else { return }
        let old = Set(displays.map(\.uuid))
        refreshDisplays()
        let now = Set(displays.map(\.uuid))
        if old != now {
            Log.info("Displays changed: \(displays.map(\.name))")
            // Strips of displays that went away join the main display's strip.
            let mainKey = (displays.first { $0.isMain } ?? displays.first).flatMap { activeKey(for: $0) }
            for (key, s) in strips where !now.contains(key.display) {
                if let mk = mainKey {
                    var t = strips[mk] ?? Strip()
                    for c in s.columns { for wid in c.windows { t.insert(wid, width: c.width, at: .end, focus: false); windows[wid]?.key = mk } }
                    strips[mk] = t
                }
                strips[key] = nil
                layouts[key] = nil
            }
        }
        TrackpadWatcher.shared.restart()
        syncVisibility()
        relayoutAll(animated: false)
        syncFocus()
    }

    // MARK: - Initial arrangement and session restore

    private func arrangeInitial() {
        let onScreen = WindowServer.all(onScreenOnly: true)
        var groups: [StripKey: [TrackedWindow]] = [:]
        for w in windows.values where !w.floating && onScreen[w.id] != nil && !w.element.isMinimized && !w.element.isFullScreen {
            if let k = activeKey(forWindow: w) { groups[k, default: []].append(w) }
        }
        let focusedNow = osFocusedWindowID()
        for (key, list) in groups {
            var strip = Strip()
            var remaining = list
            if config.restoreSession, let session,
               let snap = SessionRestore.snapshot(in: session, displayUUID: key.display, spaceID: key.space, spaceIndex: spaceIndex(key)) {
                var used = Set<WindowID>()
                strip = SessionRestore.restore(snap, live: list.map(\.ref), used: &used)
                remaining = list.filter { !used.contains($0.id) }
                if !used.isEmpty { Log.info("Restored \(used.count) windows on \(key)") }
            }
            let d = display(uuid: key.display)!
            for w in remaining.sorted(by: { ($0.element.frame?.x ?? 0) < ($1.element.frame?.x ?? 0) }) {
                strip.insert(w.id, width: openingWidth(for: w, on: d), at: .end, focus: false)
            }
            if let f = focusedNow, strip.contains(f) { strip.focus(window: f) }
            if strip.focused == nil, !strip.isEmpty { strip.focused = 0 }
            strips[key] = strip
            for wid in strip.allWindows { windows[wid]?.key = key }
        }
        relayoutAll(animated: true)
    }

    func snapshot() -> SessionSnapshot {
        let strips = self.strips.filter { !$0.value.isEmpty }.map { key, s in
            StripSnapshot(displayUUID: key.display, spaceID: key.space, spaceIndex: spaceIndex(key), strip: s) { self.windows[$0]?.ref }
        }
        return SessionSnapshot(strips: strips, floating: windows.values.filter(\.floating).map(\.ref))
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            SessionStore.save(self.snapshot())
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    /// Brings windows that are parked at the screen edges back into view (when pausing or quitting).
    func releaseParked() {
        for (key, r) in layouts {
            guard let d = display(uuid: key.display) else { continue }
            var i = 0
            for pl in r.placements {
                guard case .hidden = pl.visibility, let w = windows[pl.window] else { continue }
                let wv = min(pl.frame.w, d.visible.w - 80), hv = min(pl.frame.h, d.visible.h - 80)
                let off = Double(i % 8) * 30
                let f = Rect(x: d.visible.x + 40 + off, y: d.visible.y + 30 + off, w: wv, h: hv)
                w.element.setSize(CGSize(width: f.w, height: f.h))
                w.element.setPosition(CGPoint(x: f.x, y: f.y))
                i += 1
            }
        }
    }

    // MARK: - Layout

    func params(for d: Display) -> LayoutParams {
        LayoutParams(screen: d.frame, area: d.visible, innerGap: config.innerGap, outerGap: config.outerGap,
                     centerMode: config.centerMode, sparse: config.sparse, tabBarHeight: config.tabBarHeight,
                     keepOriginalHeight: config.keepOriginalHeight)
    }

    private func constraints(for s: Strip) -> [WindowID: WindowConstraints] {
        var c: [WindowID: WindowConstraints] = [:]
        for wid in s.allWindows { if let w = windows[wid] { c[wid] = w.constraints } }
        return c
    }

    func relayoutAll(animated: Bool = true) {
        for key in strips.keys where isActive(key) { relayout(key, animated: animated) }
    }

    func relayout(_ key: StripKey, animated: Bool = true, reveal: Bool = true, center: Bool = false) {
        guard isRunning, var s = strips[key], let d = display(uuid: key.display), isActive(key) else { return }
        s.normalize()
        let p = params(for: d)
        let cons = constraints(for: s)
        if reveal || center { s.scroll = Layout.scrollToReveal(s, p, constraints: cons, forceCenter: center) }
        strips[key] = s
        let r = Layout.compute(s, p, constraints: cons)
        layouts[key] = r
        let others = displays.filter { $0.uuid != d.uuid }.map(\.frame)
        for pl in r.placements {
            guard let w = windows[pl.window] else { continue }
            var f = pl.frame.rounded()
            if case .hidden(let side) = pl.visibility {
                f = Parking.frame(size: f.size, side: side, screen: d.frame, others: others, y: f.y)
            }
            if !animator.isAnimating(w.id), let lf = w.lastFrame, lf.isClose(to: f, tolerance: 0.5),
               CACurrentMediaTime() - w.lastSetTime < 5 || w.element.frame.map({ $0.isClose(to: f, tolerance: 1) }) == true {
                continue
            }
            animator.move(w.id, element: w.element, pid: w.pid, from: w.lastFrame ?? w.element.frame, to: f,
                          animated: animated && config.animate, response: config.animationResponse)
        }
        animator.kick()
        if !animated || !config.animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.readBack() }
        }
        scheduleSave()
        notifyLayout()
    }

    private func notifyLayout() { layoutListeners.forEach { $0() } }

    // MARK: - Focus

    private func osFocusedWindowID() -> WindowID? {
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
        guard let w else { notifyLayout(); return }
        if w.key == nil && !w.floating { syncVisibility() }
        if let key = w.key, var s = strips[key] {
            lastKey = key
            let changed = s.focus(window: wid)
            strips[key] = s
            if changed { relayout(key, reveal: true) } else if needsReveal(key) { relayout(key, reveal: true) }
        }
        notifyLayout()
    }

    private func needsReveal(_ key: StripKey) -> Bool {
        guard let s = strips[key], let f = s.focused, let r = layouts[key], r.columnVisibility.indices.contains(f) else { return false }
        return r.columnVisibility[f] != .visible
    }

    func focusOS(_ wid: WindowID) {
        guard let w = windows[wid] else { return }
        pendingFocus = (wid, CACurrentMediaTime() + 0.6)
        focusedWindowID = wid
        let appEl = AXElement.app(w.pid)
        appEl.set(kAXFrontmostAttribute, true)
        w.element.set(kAXMainAttribute, true)
        w.element.perform(kAXRaiseAction)
        if let app = NSRunningApplication(processIdentifier: w.pid), !app.isActive {
            app.activate(options: [])
        }
        notifyLayout()
    }

    func focus(window wid: WindowID) {
        guard let w = windows[wid] else { return }
        if let key = w.key, var s = strips[key] {
            s.focus(window: wid)
            strips[key] = s
            relayout(key, reveal: true)
        }
        focusOS(wid)
    }

    // MARK: - Commands

    /// The strip commands act on: the focused window's, else the one under the mouse.
    func commandKey() -> StripKey? {
        if let f = focusedWindowID, let k = windows[f]?.key, isActive(k) { return k }
        if let d = display(at: Displays.mouseLocation), let k = activeKey(for: d) { return k }
        if let k = lastKey, isActive(k) { return k }
        return activeKeys.first
    }

    func perform(_ cmd: Command) {
        commandListeners.forEach { $0(cmd) }
        switch cmd {
        case .toggleTiling: setTiling(!config.tilingEnabled); return
        case .showShortcuts: UIHub.shared.showCheatSheet(); return
        case .openSettings: UIHub.shared.openSettings(); return
        case .showStrip: UIHub.shared.showIndicator(for: commandKey(), duration: 2.5); return
        case .arrange: restart(); return
        default: break
        }
        guard isRunning else { return }
        if cmd == .toggleFloat { toggleFloat(); return }
        if cmd == .moveToNextDisplay || cmd == .moveToPreviousDisplay { moveToDisplay(cmd == .moveToNextDisplay ? 1 : -1); return }
        guard let key = commandKey(), var s = strips[key], !s.isEmpty else { return }
        if s.focused == nil { s.focused = 0 }
        let before = s.focusedWindow
        var changed = false, center = false, flash = false
        let presets = config.widthPresets
        switch cmd {
        case .focusLeft: changed = s.focusLeft(); flash = true
        case .focusRight: changed = s.focusRight(); flash = true
        case .focusUp: changed = s.focusVertical(-1)
        case .focusDown: changed = s.focusVertical(1)
        case .focusFirst: changed = s.focusFirst(); flash = true
        case .focusLast: changed = s.focusLast(); flash = true
        case .focusBack: if let p = s.previousFocusedWindow { changed = s.focus(window: p); flash = true }
        case .focus1, .focus2, .focus3, .focus4, .focus5, .focus6, .focus7, .focus8, .focus9:
            changed = s.focusColumn((cmd.focusIndex ?? 1) - 1); flash = true
        case .moveLeft: changed = s.moveColumn(-1); flash = true
        case .moveRight: changed = s.moveColumn(1); flash = true
        case .moveUp: changed = s.moveWindowVertical(-1)
        case .moveDown: changed = s.moveWindowVertical(1)
        case .moveFirst: changed = s.moveColumnToEdge(last: false); flash = true
        case .moveLast: changed = s.moveColumnToEdge(last: true); flash = true
        case .cycleWidth: changed = s.cycleWidth(presets: presets)
        case .cycleWidthBack: changed = s.cycleWidth(presets: presets, forward: false)
        case .fullWidth: changed = s.toggleFullWidth()
        case .center: changed = true; center = true
        case .wider: changed = s.adjustWidth(by: 0.05)
        case .narrower: changed = s.adjustWidth(by: -0.05)
        case .taller: changed = s.adjustHeight(by: 0.1)
        case .shorter: changed = s.adjustHeight(by: -0.1)
        case .equalizeHeights: changed = s.equalizeHeights()
        case .stackLeft: changed = s.consume(into: .left)
        case .stackRight: changed = s.consume(into: .right)
        case .popLeft: changed = s.expel(to: .left)
        case .popRight: changed = s.expel(to: .right)
        case .toggleTabbed: changed = s.toggleTabbed()
        case .pinLeft: changed = s.togglePin(.left); flash = true
        case .pinRight: changed = s.togglePin(.right); flash = true
        case .scrollLeft, .scrollRight:
            strips[key] = s
            scrollStrip(key, by: cmd == .scrollLeft ? -0.5 : 0.5)
            return
        default: break
        }
        if (cmd == .cycleWidth || cmd == .fullWidth || cmd == .wider || cmd == .narrower), let wid = s.focusedWindow {
            windows[wid]?.constraints.minWidth = nil
        }
        strips[key] = s
        guard changed else {
            if flash { UIHub.shared.flashIndicator(for: key) }
            return
        }
        lastKey = key
        if let after = s.focusedWindow, after != before { focusOS(after) }
        relayout(key, reveal: true, center: center)
        if flash && config.showIndicatorOnScroll { UIHub.shared.flashIndicator(for: key) }
    }

    private func toggleFloat() {
        guard let wid = focusedWindowID ?? commandKey().flatMap({ strips[$0]?.focusedWindow }), let w = windows[wid] else { return }
        if w.floating {
            w.floating = false
            // Goes back to where it was floated from (attach uses the remembered slot).
            if let k = attach(w, focus: true) { relayout(k) }
            Log.info("Tiled \(w.appName)")
        } else if let key = w.key, let d = display(uuid: key.display) {
            detach(w, relayoutNow: false)
            w.floating = true
            animator.cancel(wid)
            let size = Size(w: min(max(w.openingFrame.w, 400), d.visible.w * 0.8), h: min(max(w.openingFrame.h, 300), d.visible.h * 0.8))
            let f = Rect(x: d.visible.midX - size.w / 2, y: d.visible.midY - size.h / 2, w: size.w, h: size.h).rounded()
            animator.move(wid, element: w.element, pid: w.pid, from: w.lastFrame, to: f, animated: config.animate, response: config.animationResponse)
            relayout(key)
            focusOS(wid)
            Log.info("Floated \(w.appName)")
        }
        notifyLayout()
    }

    private func moveToDisplay(_ delta: Int) {
        guard displays.count > 1, let key = commandKey(), var s = strips[key], let wid = s.focusedWindow, let w = windows[wid] else { return }
        let sorted = displays.sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        guard let i = sorted.firstIndex(where: { $0.uuid == key.display }) else { return }
        var j = i
        var target: StripKey?
        for _ in 0..<sorted.count {
            j = (j + delta + sorted.count) % sorted.count
            if let k = activeKey(for: sorted[j]), k != key { target = k; break }
        }
        guard let target else { return }
        let width = s.locate(wid).map { s.columns[$0.column].width } ?? config.defaultWidth
        s.remove(wid)
        strips[key] = s
        var t = strips[target] ?? Strip()
        t.insert(wid, width: width, at: .afterFocused, focus: true)
        strips[target] = t
        w.key = target
        animator.mover.invalidate(wid)
        relayout(key)
        relayout(target)
        focusOS(wid)
        UIHub.shared.flashIndicator(for: target)
    }

    private func scrollStrip(_ key: StripKey, by fraction: Double) {
        guard var s = strips[key], let d = display(uuid: key.display) else { return }
        let p = params(for: d)
        let cons = constraints(for: s)
        let (lo, hi) = SwipeMath.scrollLimits(s, p, constraints: cons)
        let projected = min(hi, max(lo, s.scroll + fraction * (d.visible.w - 2 * config.outerGap)))
        if let c = SwipeMath.settleColumn(s, p, projectedScroll: projected, constraints: cons) {
            s.scroll = projected
            s.focusColumn(c)
        }
        strips[key] = s
        relayout(key, reveal: true)
        if let f = s.focusedWindow { focusOS(f) }
        UIHub.shared.flashIndicator(for: key)
    }

    // MARK: - Interactive scrolling (trackpad swipes, ⌃⌥ + scroll wheel)

    func interactiveBegin() {
        guard isRunning else { return }
        let mouse = Displays.mouseLocation
        swipeKey = display(at: mouse).flatMap { activeKey(for: $0) } ?? commandKey()
        if let k = swipeKey { swipeRaw = strips[k]?.scroll ?? 0 }
    }

    func interactiveScroll(points: Double) {
        guard isRunning, let key = swipeKey, var s = strips[key], let d = display(uuid: key.display) else { return }
        let p = params(for: d)
        let (lo, hi) = SwipeMath.scrollLimits(s, p, constraints: constraints(for: s))
        swipeRaw += points
        s.scroll = SwipeMath.rubberBand(swipeRaw, min: lo, max: hi)
        strips[key] = s
        relayout(key, animated: false, reveal: false)
        UIHub.shared.flashIndicator(for: key)
    }

    func interactiveEnd(velocityPoints: Double) {
        guard isRunning, let key = swipeKey, var s = strips[key], let d = display(uuid: key.display) else { return }
        swipeKey = nil
        let p = params(for: d)
        let cons = constraints(for: s)
        let (lo, hi) = SwipeMath.scrollLimits(s, p, constraints: cons)
        let projected = min(hi, max(lo, s.scroll + velocityPoints * 0.18))
        let before = s.focusedWindow
        if let c = SwipeMath.settleColumn(s, p, projectedScroll: projected, constraints: cons) {
            s.scroll = projected
            s.focusColumn(c)
        }
        strips[key] = s
        relayout(key, animated: true, reveal: true)
        if let f = s.focusedWindow, f != before { focusOS(f) }
        UIHub.shared.flashIndicator(for: key)
    }

    // MARK: - Indicator support

    func moveColumn(in key: StripKey, from: Int, to: Int) {
        guard var s = strips[key] else { return }
        if s.moveColumn(from: from, to: to) {
            strips[key] = s
            relayout(key, reveal: true)
        }
    }

    func focusColumn(in key: StripKey, index: Int) {
        guard var s = strips[key], s.columns.indices.contains(index) else { return }
        s.focusColumn(index)
        strips[key] = s
        relayout(key, reveal: true)
        if let f = s.focusedWindow { focusOS(f) }
    }

    func windowsUnderMouseFocusable() -> WindowID? {
        let m = Displays.mouseLocation
        for (key, r) in layouts where isActive(key) {
            for pl in r.placements where pl.visibility == .visible && pl.frame.contains(m) { return pl.window }
        }
        return nil
    }

    // MARK: - State for the CLI and tests

    func stateJSON() -> String {
        func rect(_ r: Rect?) -> Any { r.map { [$0.x, $0.y, $0.w, $0.h] } ?? NSNull() }
        func opt(_ v: Any?) -> Any { v ?? NSNull() }
        var root: [String: Any] = [
            "version": AppInfo.version,
            "running": isRunning,
            "tiling": config.tilingEnabled,
            "accessibility": AXPermission.isTrusted,
            "focused": opt(focusedWindowID.map { Int($0) }),
        ]
        root["displays"] = displays.map { d -> [String: Any] in
            [
                "uuid": d.uuid, "name": d.name, "frame": rect(d.frame), "visible": rect(d.visible), "main": d.isMain,
                "excluded": config.excludedDisplays.contains(d.uuid),
                "space": opt(activeKey(for: d).map { Int($0.space) }),
            ]
        }
        root["strips"] = strips.map { key, s -> [String: Any] in
            let r = layouts[key]
            return [
                "display": key.display, "space": Int(key.space), "active": isActive(key),
                "focused": opt(s.focused), "scroll": s.scroll,
                "viewport": rect(r?.viewport),
                "columns": s.columns.enumerated().map { ci, c -> [String: Any] in
                    [
                        "width": c.width, "mode": c.mode.rawValue, "pin": opt(c.pin?.rawValue), "active": c.active,
                        "visibility": r.flatMap { $0.columnVisibility.indices.contains(ci) ? $0.columnVisibility[ci].name : nil } ?? "unknown",
                        "windows": c.windows.map { wid -> [String: Any] in
                            let w = windows[wid]
                            let pl = r?.placement(for: wid)
                            return [
                                "id": Int(wid), "app": w?.appName ?? "?", "bundle": w?.bundleID ?? "", "title": w?.title ?? "",
                                "target": rect(pl?.frame), "visibility": pl?.visibility.name ?? "unknown",
                                "frame": rect(w?.element.frame),
                            ]
                        },
                    ]
                },
            ]
        }
        root["floating"] = windows.values.filter(\.floating).map { w -> [String: Any] in
            ["id": Int(w.id), "app": w.appName, "title": w.title, "frame": rect(w.element.frame)]
        }
        root["untiled"] = windows.values.filter { !$0.floating && $0.key == nil }.map { w -> [String: Any] in
            ["id": Int(w.id), "app": w.appName, "title": w.title]
        }
        guard let d = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}
#endif
