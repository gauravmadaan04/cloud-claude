#if os(macOS)
import AppKit
import QuartzCore
import RibbonCore

/// A tiled window the user is dragging by its title bar or an edge.
struct DragSession {
    let wid: WindowID
    let key: ScreenKey
    let tile: Int
    /// The tile's frame when the drag began.
    let start: Rect
    var resizing: Bool
    var flags: NSEvent.ModifierFlags = []
    var lastLive: CFTimeInterval = 0
}

extension WindowManager {
    // MARK: - Commands

    func perform(_ cmd: Command) {
        commandListeners.forEach { $0(cmd) }
        switch cmd {
        case .toggleTiling: setTiling(!config.tilingEnabled); return
        case .showShortcuts: UIHub.shared.showCheatSheet(); return
        case .openSettings: UIHub.shared.openSettings(); return
        case .tabView: UIHub.shared.tabView.trigger(forward: true); return
        case .tabViewBack: UIHub.shared.tabView.trigger(forward: false); return
        case .noPeek: toggleNoPeek(); return
        default: break
        }
        guard isRunning else { return }
        switch cmd {
        case .retile: retile()
        case .toggleFloat: toggleFloat()
        case .focusNext: focusAdjacent(1)
        case .focusPrevious: focusAdjacent(-1)
        case .cleanSpace: toggleCleanSpace()
        case .nextDisplay: moveToDisplay(step: 1)
        case .previousDisplay: moveToDisplay(step: -1)
        case .tile1, .tile2, .tile3, .tile4: if let key = commandKey() { setCapacity(cmd.tileCount ?? 3, for: key) }
        case .toggleLayout: if let key = commandKey() { setLayout(layoutKind(key) == .grid ? .columns : .grid, for: key) }
        default: screenCommand(cmd)
        }
    }

    /// Commands that act on the window in use and its screen.
    private func screenCommand(_ cmd: Command) {
        guard let key = commandKey(), var b = boards[key], !b.isEmpty, let d = display(uuid: key.display) else { return }
        let wid = focusedWindowID.flatMap { b.contains($0) ? $0 : nil } ?? b.active ?? b.tiles[0].showing
        guard let i = b.tileIndex(of: wid) else { return }
        let frames = tileFrames[key] ?? []
        switch cmd {
        case .swapLeft, .swapRight, .swapUp, .swapDown:
            guard let dir = cmd.direction else { return }
            b.show(wid)
            if let j = TileLayout.neighbor(of: i, dir, in: frames) {
                b.swap(i, j)
                b.setActive(wid)
                boards[key] = b
                relayout(key)
            } else {
                boards[key] = b
                moveToDisplay(wid, from: key, direction: dir)
            }
        case .makePrimary:
            guard i != 0 else { return }
            b.show(wid)
            b.makePrimary(i)
            b.setActive(wid)
            boards[key] = b
            relayout(key)
        case .stackNext, .stackPrevious:
            guard b.cycle(tile: i, cmd == .stackNext ? 1 : -1) else { return }
            boards[key] = b
            focusOS(b.tiles[i].showing)
        case .grow, .shrink:
            let grow = cmd == .grow
            if let s = TileLayout.resized(b.splits, tile: i, by: grow ? 0.05 : -0.05, count: b.tiles.count, arrangement(key, d)) {
                b.splits = s
                boards[key] = b
                relayout(key)
            } else {
                UIHub.shared.notice(grow ? "Maximum size reached" : "Minimum size reached",
                                    symbol: grow ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left", on: d)
                NSSound.beep()
            }
        case .resetSizes:
            resetSizes(key)
        case .focusMode:
            b.zoomed = b.zoomed == wid ? nil : wid
            boards[key] = b
            relayout(key)
            if b.zoomed != nil { focusOS(wid) }
            UIHub.shared.notice(b.zoomed != nil ? "Focus" : "Back to the layout",
                                symbol: b.zoomed != nil ? "scope" : "square.grid.2x2", on: d)
        default:
            break
        }
    }

    /// Lays everything out afresh, giving windows that floated for lack of room another chance.
    func retile() {
        guard isRunning else { start(); return }
        for w in windows.values where w.overflowed { w.overflowed = false; w.floating = false }
        syncVisibility()
        relayoutAll(animated: true)
        haptic()
    }

    /// Equal sizes again; minimum sizes are learned afresh.
    func resetSizes(_ key: ScreenKey) {
        guard var b = boards[key] else { return }
        b.splits = Splits()
        for w in b.windows { windows[w]?.minSize = Size(w: 0, h: 0) }
        boards[key] = b
        relayout(key)
    }

    func setCapacity(_ n: Int, for key: ScreenKey) {
        guard let d = display(uuid: key.display) else { return }
        var b = boards[key] ?? Board()
        b.capacity = n
        boards[key] = b
        fillFromOverflow(key)
        relayout(key)
        let eff = capacity(key, d)
        UIHub.shared.notice(eff == 1 ? "1 window on this screen" : "\(eff) windows on this screen", symbol: "rectangle.split.2x2", on: d)
    }

    func setLayout(_ kind: LayoutKind, for key: ScreenKey) {
        guard let d = display(uuid: key.display) else { return }
        var b = boards[key] ?? Board()
        b.layout = kind
        boards[key] = b
        fillFromOverflow(key)
        relayout(key)
        UIHub.shared.notice(kind.title, symbol: kind == .grid ? "square.grid.2x2" : "rectangle.split.3x1", on: d)
    }

    func toggleFloat() {
        guard let wid = focusedWindowID ?? commandKey().flatMap({ boards[$0]?.active }), let w = windows[wid] else { return }
        if w.floating {
            w.floating = false
            w.overflowed = false
            // Goes back to where it was floated from (detach remembered the spot).
            if let k = attach(w, activate: true) { relayout(k) }
            Log.info("Tiled \(w.appName)")
        } else if let key = w.key, let d = display(uuid: key.display) {
            detach(w, relayoutNow: false)
            w.floating = true
            animator.cancel(wid)
            animator.move(wid, element: w.element, pid: w.pid, from: w.lastFrame, to: centered(w, on: d), animated: config.animate,
                          response: config.animationResponse)
            fillFromOverflow(key)
            relayout(key)
            focusOS(wid)
            Log.info("Floated \(w.appName)")
        }
        notifyLayout()
    }

    /// Goes to the next window on screen: tiles in order, display by display.
    private func focusAdjacent(_ step: Int) {
        let order = displays.sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
            .compactMap { activeKey(for: $0) }
            .flatMap { boards[$0]?.showing ?? [] }
        guard !order.isEmpty else { return }
        let n = order.count
        let cur = focusedWindowID.flatMap { order.firstIndex(of: $0) } ?? (step > 0 ? -1 : n)
        focusOS(order[((cur + step) % n + n) % n])
    }

    // MARK: - Moving between displays

    private func moveToDisplay(step: Int) {
        guard displays.count > 1, let wid = focusedWindowID, let w = windows[wid], let key = w.key else { return }
        let sorted = displays.sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        guard let i = sorted.firstIndex(where: { $0.uuid == key.display }) else { return }
        let target = sorted[((i + step) % sorted.count + sorted.count) % sorted.count]
        guard let tk = activeKey(for: target), tk != key else { return }
        moveWindow(w, from: key, to: tk, entering: nil)
    }

    private func moveToDisplay(_ wid: WindowID, from key: ScreenKey, direction dir: Direction) {
        guard let w = windows[wid], let src = display(uuid: key.display), let dd = neighborDisplay(of: src, dir),
              let tk = activeKey(for: dd) else { return }
        moveWindow(w, from: key, to: tk, entering: dir)
    }

    /// The display next to another in a direction, as arranged in System Settings.
    func neighborDisplay(of src: Display, _ dir: Direction) -> Display? {
        let f = src.frame
        let candidates = displays.filter { d in
            guard d.uuid != src.uuid else { return false }
            let g = d.frame
            switch dir {
            case .left: return g.maxX <= f.minX + 2 && min(f.maxY, g.maxY) > max(f.minY, g.minY)
            case .right: return g.minX >= f.maxX - 2 && min(f.maxY, g.maxY) > max(f.minY, g.minY)
            case .up: return g.maxY <= f.minY + 2 && min(f.maxX, g.maxX) > max(f.minX, g.minX)
            case .down: return g.minY >= f.maxY - 2 && min(f.maxX, g.maxX) > max(f.minX, g.minX)
            }
        }
        return candidates.min { hypot($0.frame.midX - f.midX, $0.frame.midY - f.midY) < hypot($1.frame.midX - f.midX, $1.frame.midY - f.midY) }
    }

    /// Carries a window to another screen: a tile of its own if there's room, else a swap or a stack.
    private func moveWindow(_ w: TrackedWindow, from key: ScreenKey, to tk: ScreenKey, entering dir: Direction?) {
        guard let td = display(uuid: tk.display), var sb = boards[key] else { return }
        var tb = boards[tk] ?? Board()
        let cap = capacity(tk, td)
        if tb.tiles.count < cap {
            sb.remove(w.id)
            tb.add(w.id, capacity: cap, stackWhenFull: false)
        } else {
            let frames = tileFrames[tk] ?? TileLayout.frames(count: tb.tiles.count, arrangement(tk, td), area: area(for: td),
                                                             gap: config.spacing, splits: tb.splits)
            let t = entryTile(frames, entering: dir) ?? tb.activeTile ?? 0
            guard tb.tiles.indices.contains(t) else { return }
            if config.intoFull == .swap {
                let other = tb.tiles[t].showing
                sb.replace(w.id, with: other)
                tb.replace(other, with: w.id)
                tb.setActive(w.id)
                windows[other]?.key = key
                animator.mover.invalidate(other)
            } else {
                sb.remove(w.id)
                tb.push(w.id, onto: t)
            }
        }
        boards[key] = sb
        boards[tk] = tb
        w.key = tk
        detached[w.id] = nil
        animator.mover.invalidate(w.id)
        fillFromOverflow(key)
        relayout(key)
        relayout(tk)
        focusOS(w.id)
    }

    /// The tile a window lands in when it comes onto a full screen from one side.
    private func entryTile(_ frames: [Rect], entering dir: Direction?) -> Int? {
        guard let dir, !frames.isEmpty else { return nil }
        let idx = Array(frames.indices)
        switch dir {
        case .right: return idx.min { (frames[$0].minX, frames[$0].minY) < (frames[$1].minX, frames[$1].minY) }
        case .left: return idx.max { (frames[$0].maxX, -frames[$0].minY) < (frames[$1].maxX, -frames[$1].minY) }
        case .down: return idx.min { (frames[$0].minY, frames[$0].minX) < (frames[$1].minY, frames[$1].minX) }
        case .up: return idx.max { (frames[$0].maxY, -frames[$0].minX) < (frames[$1].maxY, -frames[$1].minX) }
        }
    }

    // MARK: - Modes

    func toggleNoPeek() {
        noPeek.toggle()
        let d = commandKey().flatMap { display(uuid: $0.display) }
        UIHub.shared.notice(noPeek ? "No peek" : "No peek off", symbol: noPeek ? "eye.slash" : "eye", on: d)
        notifyLayout()
    }

    func toggleCleanSpace() {
        guard let key = commandKey(), let d = display(uuid: key.display) else { return }
        var b = boards[key] ?? Board()
        if cleanSpace.contains(d.uuid) {
            cleanSpace.remove(d.uuid)
            b.zoomed = nil
        } else {
            cleanSpace.insert(d.uuid)
            if let wid = focusedWindowID, b.contains(wid) { b.zoomed = wid }
            haptic()
        }
        boards[key] = b
        relayout(key)
        notifyLayout()
    }

    /// Clean Space ends when the Mac sleeps or locks.
    func endCleanSpace() {
        guard !cleanSpace.isEmpty else { return }
        cleanSpace.removeAll()
        for (key, var b) in boards where b.zoomed != nil {
            b.zoomed = nil
            boards[key] = b
        }
        relayoutAll(animated: false)
        notifyLayout()
    }

    func setAppTiles(_ on: Bool, bundleID: String, name: String) {
        store.config.setTiles(on, bundleID: bundleID, name: name)
    }

    func haptic() {
        guard config.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: - Dragging: ⌘-drag swaps, ⌥⌘-drag stacks, edges resize

    var mouseIsDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 || simulatedDrag }

    func userDragged(_ w: TrackedWindow, key: ScreenKey, actual: Rect, resized: Bool) {
        if drag?.wid != w.id {
            endDrag()
            guard let b = boards[key], let i = b.tileIndex(of: w.id), let frames = tileFrames[key], frames.indices.contains(i),
                  let disp = display(uuid: key.display) else { return }
            let start = b.zoomed == w.id ? area(for: disp) : frames[i]
            let sizeChanged = abs(actual.w - start.w) > 2 || abs(actual.h - start.h) > 2
            drag = DragSession(wid: w.id, key: key, tile: i, start: start, resizing: resized && sizeChanged)
            installDragMonitors()
        }
        guard var d = drag else { return }
        if resized, abs(actual.w - d.start.w) > 2 || abs(actual.h - d.start.h) > 2 { d.resizing = true }
        w.lastFrame = actual
        let now = CACurrentMediaTime()
        if d.resizing, now - d.lastLive > 1.0 / 30, let disp = display(uuid: key.display), var b = boards[key], b.zoomed != w.id {
            // The neighbours make room as you drag.
            d.lastLive = now
            b.splits = TileLayout.splits(afterResizing: d.tile, from: d.start, to: actual, count: b.tiles.count, arrangement(key, disp),
                                         area: area(for: disp), gap: config.spacing, splits: b.splits)
            boards[key] = b
            drag = d
            relayout(key, animated: false, except: w.id)
            return
        }
        drag = d
        if !d.resizing { updateDropHint() }
    }

    private func installDragMonitors() {
        guard dragMonitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] e in
            let flags = e.modifierFlags
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.finishDrag(flags: flags) }
        }) {
            dragMonitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .flagsChanged], handler: { [weak self] e in
            self?.drag?.flags = e.modifierFlags
            self?.updateDropHint()
        }) {
            dragMonitors.append(m)
        }
        // Safety net in case the button came up without us seeing it.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let d = self.drag else { return }
            if !self.mouseIsDown { self.finishDrag(flags: d.flags) }
        }
        RunLoop.main.add(t, forMode: .common)
        dragTimer = t
    }

    func endDrag() {
        dragMonitors.forEach { NSEvent.removeMonitor($0) }
        dragMonitors.removeAll()
        dragTimer?.invalidate()
        dragTimer = nil
        drag = nil
        UIHub.shared.dropHint.hide()
    }

    private func updateDropHint() {
        guard let d = drag, !d.resizing, d.flags.contains(.command),
              let (key, i) = dropTarget(at: Displays.mouseLocation, excluding: d.wid), let f = tileFrames[key]?[i] else {
            UIHub.shared.dropHint.hide()
            return
        }
        UIHub.shared.dropHint.show(frame: f, stacking: d.flags.contains(.option))
    }

    /// The tile under a point, on any screen, other than the dragged window's own.
    func dropTarget(at p: Point, excluding wid: WindowID) -> (ScreenKey, Int)? {
        for (key, frames) in tileFrames where isActive(key) {
            guard let b = boards[key] else { continue }
            for (i, f) in frames.enumerated() where f.contains(p) && b.tiles.indices.contains(i) && b.tiles[i].showing != wid {
                return (key, i)
            }
        }
        return nil
    }

    func finishDrag(flags: NSEvent.ModifierFlags) {
        guard let d = drag else { return }
        endDrag()
        guard let w = windows[d.wid], let key = w.key, var b = boards[key] else { return }
        let actual = w.element.frame ?? w.lastFrame
        w.lastFrame = actual
        animator.mover.invalidate(w.id)
        if d.resizing {
            if let disp = display(uuid: key.display), b.zoomed != w.id, let actual {
                b.splits = TileLayout.splits(afterResizing: d.tile, from: d.start, to: actual, count: b.tiles.count, arrangement(key, disp),
                                             area: area(for: disp), gap: config.spacing, splits: b.splits)
                boards[key] = b
                Log.info("Resized next to \(w.appName)")
            }
            relayout(key)
            return
        }
        let mouse = Displays.mouseLocation
        if flags.contains(.command), let (tk, ti) = dropTarget(at: mouse, excluding: w.id) {
            if flags.contains(.option) { stack(w, onto: ti, of: tk) } else { swap(w, withTile: ti, of: tk) }
            return
        }
        // Dropped on another screen: it joins as the newest window there, or comes back if that screen is full.
        if let dd = display(at: mouse), dd.uuid != key.display, let tk = activeKey(for: dd),
           (boards[tk]?.tiles.count ?? 0) < capacity(tk, dd) {
            b.remove(w.id)
            boards[key] = b
            w.key = nil
            detached[w.id] = nil
            attach(w, activate: true, to: tk)
            fillFromOverflow(key)
            relayout(key)
            relayout(tk)
            focusOS(w.id)
            return
        }
        relayout(key)
    }

    private func swap(_ w: TrackedWindow, withTile ti: Int, of tk: ScreenKey) {
        guard let key = w.key, var sb = boards[key] else { return }
        if tk == key {
            guard let i = sb.tileIndex(of: w.id) else { return }
            sb.show(w.id)
            sb.swap(i, ti)
            sb.setActive(w.id)
            boards[key] = sb
            relayout(key)
        } else {
            guard var tb = boards[tk], tb.tiles.indices.contains(ti) else { return }
            let other = tb.tiles[ti].showing
            sb.replace(w.id, with: other)
            tb.replace(other, with: w.id)
            tb.setActive(w.id)
            boards[key] = sb
            boards[tk] = tb
            w.key = tk
            windows[other]?.key = key
            animator.mover.invalidate(other)
            relayout(key)
            relayout(tk)
        }
        Log.info("Swapped \(w.appName)")
        focusOS(w.id)
    }

    private func stack(_ w: TrackedWindow, onto ti: Int, of tk: ScreenKey) {
        guard let key = w.key, var sb = boards[key] else { return }
        if tk == key {
            sb.move(w.id, toStackOf: ti)
            boards[key] = sb
        } else {
            guard var tb = boards[tk] else { return }
            sb.remove(w.id)
            tb.push(w.id, onto: ti)
            boards[key] = sb
            boards[tk] = tb
            w.key = tk
            fillFromOverflow(key)
            relayout(tk)
        }
        relayout(key)
        Log.info("Stacked \(w.appName)")
        focusOS(w.id)
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
            "stageManagerPause": pausedForStageManager,
            "focused": opt(focusedWindowID.map { Int($0) }),
            "noPeek": noPeek,
            "cleanSpace": Array(cleanSpace),
        ]
        root["displays"] = displays.map { d -> [String: Any] in
            [
                "uuid": d.uuid, "name": d.name, "frame": rect(d.frame), "visible": rect(d.visible), "main": d.isMain,
                "area": rect(area(for: d)), "space": opt(activeKey(for: d).map { Int($0.space) }),
            ]
        }
        root["screens"] = boards.map { key, b -> [String: Any] in
            let d = display(uuid: key.display)
            let frames = tileFrames[key] ?? []
            return [
                "display": key.display, "space": Int(key.space), "active": isActive(key),
                "layout": layoutKind(key).rawValue,
                "arrangement": d.map { arrangement(key, $0).rawValue } ?? "unknown",
                "capacity": d.map { capacity(key, $0) } ?? 0,
                "splits": ["x": b.splits.x, "leftY": b.splits.leftY, "rightY": b.splits.rightY, "weights": b.splits.weights] as [String: Any],
                "zoomed": opt(b.zoomed.map { Int($0) }),
                "activeWindow": opt(b.active.map { Int($0) }),
                "tiles": b.tiles.enumerated().map { i, t -> [String: Any] in
                    [
                        "frame": rect(frames.indices.contains(i) ? frames[i] : nil),
                        "showing": Int(t.showing),
                        "windows": t.windows.map { wid -> [String: Any] in
                            let w = windows[wid]
                            return [
                                "id": Int(wid), "app": w?.appName ?? "?", "bundle": w?.bundleID ?? "", "title": w?.title ?? "",
                                "frame": rect(w?.element.frame), "target": rect(targetFrame(for: wid)),
                            ]
                        },
                    ]
                },
            ]
        }
        root["floating"] = windows.values.filter(\.floating).map { w -> [String: Any] in
            ["id": Int(w.id), "app": w.appName, "title": w.title, "frame": rect(w.element.frame), "overflowed": w.overflowed]
        }
        root["untiled"] = windows.values.filter { !$0.floating && $0.key == nil }.map { w -> [String: Any] in
            ["id": Int(w.id), "app": w.appName, "title": w.title]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
