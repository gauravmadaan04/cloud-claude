#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// A borderless, click-through window used for borders, shading and other decoration.
func makeOverlayWindow(level: NSWindow.Level) -> NSWindow {
    let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.isReleasedWhenClosed = false
    w.level = level
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary, .transient]
    w.animationBehavior = .none
    return w
}

/// Windows on screen that should look "in use" or not, read from the window manager.
private struct Visible {
    let wid: WindowID
    let frame: Rect
    let active: Bool
}

private func visibleTiles() -> [Visible] {
    let wm = WindowManager.shared
    guard wm.isRunning else { return [] }
    var out: [Visible] = []
    for (key, b) in wm.boards where wm.isActive(key) {
        for t in b.tiles {
            let wid = t.showing
            // With a window filling the screen, only that one gets a highlight.
            if let z = b.zoomed, z != wid { continue }
            guard let f = wm.windows[wid]?.lastFrame else { continue }
            out.append(Visible(wid: wid, frame: f, active: wid == wm.focusedWindowID))
        }
    }
    return out
}

// MARK: - Highlight: border, all borders or glow

final class HighlightOverlays {
    private final class Ring {
        let window = makeOverlayWindow(level: .normal)
        let shape = CAShapeLayer()
        init() {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.addSublayer(shape)
            window.contentView = v
        }
    }

    private var rings: [WindowID: Ring] = [:]
    private var style: Highlight = .none

    func refresh() {
        let c = SettingsStore.shared.config
        style = c.highlight
        var keep = Set<WindowID>()
        if c.highlight != .none {
            for v in visibleTiles() where v.active || c.highlight == .allBorders {
                keep.insert(v.wid)
                let r = rings[v.wid] ?? Ring()
                rings[v.wid] = r
                draw(r, frame: v.frame, active: v.active, config: c)
                // Borders sit just above their window; a glow sits behind it so only the halo shows.
                r.window.order(c.highlight == .glow ? .below : .above, relativeTo: Int(v.wid))
            }
        }
        for (wid, r) in rings where !keep.contains(wid) {
            r.window.orderOut(nil)
            rings[wid] = nil
        }
    }

    func windowMoved(_ wid: WindowID, frame: Rect) {
        guard let r = rings[wid] else { return }
        let c = SettingsStore.shared.config
        draw(r, frame: frame, active: wid == WindowManager.shared.focusedWindowID, config: c)
    }

    private func draw(_ r: Ring, frame: Rect, active: Bool, config c: Config) {
        let color = NSColor(hex: c.highlightColor) ?? .systemPurple
        let glow = c.highlight == .glow
        let pad: CGFloat = glow ? 26 : CGFloat(c.borderWidth)
        let ns = Displays.toNS(frame).insetBy(dx: -pad, dy: -pad)
        r.window.setFrame(ns, display: false)
        let windowRect = CGRect(x: pad, y: pad, width: CGFloat(frame.w), height: CGFloat(frame.h))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        r.shape.frame = CGRect(origin: .zero, size: ns.size)
        if glow {
            r.shape.path = CGPath(roundedRect: windowRect, cornerWidth: CGFloat(c.cornerRadius), cornerHeight: CGFloat(c.cornerRadius), transform: nil)
            r.shape.fillColor = color.cgColor
            r.shape.strokeColor = nil
            r.shape.shadowColor = color.cgColor
            r.shape.shadowOpacity = 0.95
            r.shape.shadowRadius = 14
            r.shape.shadowOffset = .zero
        } else {
            let w = CGFloat(c.borderWidth)
            let ringRect = windowRect.insetBy(dx: -w / 2, dy: -w / 2)
            let radius = CGFloat(c.cornerRadius) + w / 2
            r.shape.path = CGPath(roundedRect: ringRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            r.shape.fillColor = nil
            r.shape.strokeColor = active ? color.cgColor : NSColor.white.withAlphaComponent(0.35).cgColor
            r.shape.lineWidth = active ? w : max(1, w * 0.6)
            r.shape.shadowOpacity = 0
        }
        CATransaction.commit()
    }
}

// MARK: - No peek: dim and blur everything but the window in use

final class NoPeekOverlays {
    private final class Shade {
        let window = makeOverlayWindow(level: .normal)
        let blur = NSVisualEffectView()
        let tint = NSView()
        init() {
            let root = NSView()
            blur.blendingMode = .behindWindow
            blur.material = .fullScreenUI
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            tint.wantsLayer = true
            tint.autoresizingMask = [.width, .height]
            root.addSubview(blur)
            root.addSubview(tint)
            window.contentView = root
        }
    }

    private var shades: [String: Shade] = [:]

    func refresh() {
        let wm = WindowManager.shared
        guard wm.noPeek else {
            shades.values.forEach { $0.window.orderOut(nil) }
            shades.removeAll()
            return
        }
        let c = SettingsStore.shared.config
        // The window in use: one of ours if Ribbon is in front, else the focused window.
        let ownKey = NSApp.isActive ? NSApp.keyWindow?.windowNumber : nil
        let activeID = ownKey ?? wm.focusedWindowID.map { Int($0) }
        let activeFrame = ownKey == nil ? wm.focusedWindowID.flatMap { wm.windows[$0]?.lastFrame } : NSApp.keyWindow.map { Displays.toAX($0.frame) }
        var keep = Set<String>()
        for d in wm.displays {
            keep.insert(d.uuid)
            let s = shades[d.uuid] ?? Shade()
            shades[d.uuid] = s
            s.window.setFrame(Displays.toNS(d.frame), display: false)
            s.blur.frame = s.window.contentView?.bounds ?? .zero
            s.tint.frame = s.blur.frame
            s.blur.isHidden = !c.noPeekBlur
            s.tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(c.noPeekDim).cgColor
            if let id = activeID, let f = activeFrame, f.intersectionArea(d.frame) > 0 {
                s.window.order(.below, relativeTo: id)
            } else {
                s.window.orderFrontRegardless()
            }
        }
        for (uuid, s) in shades where !keep.contains(uuid) {
            s.window.orderOut(nil)
            shades[uuid] = nil
        }
    }
}

// MARK: - Clean Space: one window on a plain background

final class CleanSpaceBackdrops {
    private var backdrops: [String: NSPanel] = [:]

    func refresh() {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        var keep = Set<String>()
        for uuid in wm.cleanSpace {
            guard let d = wm.display(uuid: uuid) else { continue }
            keep.insert(uuid)
            let p = backdrops[uuid] ?? makeBackdrop()
            backdrops[uuid] = p
            p.setFrame(Displays.toNS(d.frame), display: false)
            if let host = p.contentView as? NSHostingView<BackdropView> {
                host.rootView = BackdropView(style: c.backdrop)
            }
            let key = wm.activeKey(for: d)
            if let z = key.flatMap({ wm.boards[$0]?.zoomed }) {
                p.order(.below, relativeTo: Int(z))
            } else {
                p.orderFrontRegardless()
            }
        }
        for (uuid, p) in backdrops where !keep.contains(uuid) {
            p.orderOut(nil)
            backdrops[uuid] = nil
        }
    }

    private func makeBackdrop() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = true
        p.hasShadow = false
        p.level = .normal
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.animationBehavior = .none
        p.contentView = NSHostingView(rootView: BackdropView(style: SettingsStore.shared.config.backdrop))
        return p
    }
}

struct BackdropView: View {
    let style: Backdrop

    var body: some View {
        switch style {
        case .slate: LinearGradient(colors: [Color(white: 0.2), Color(white: 0.13)], startPoint: .top, endPoint: .bottom)
        case .fog: LinearGradient(colors: [Color(white: 0.93), Color(white: 0.85)], startPoint: .top, endPoint: .bottom)
        case .sand: LinearGradient(colors: [Color(red: 0.89, green: 0.84, blue: 0.76), Color(red: 0.8, green: 0.74, blue: 0.65)],
                                   startPoint: .top, endPoint: .bottom)
        case .aurora: Wallpaper()
        }
    }
}

// MARK: - Drop hint while ⌘-dragging

final class DropHint {
    private let window = makeOverlayWindow(level: .floating)
    private let host = NSHostingView(rootView: DropHintView(stacking: false))
    private var shownFrame: Rect?

    init() { window.contentView = host }

    func show(frame: Rect, stacking: Bool) {
        host.rootView = DropHintView(stacking: stacking)
        if shownFrame != frame {
            shownFrame = frame
            window.setFrame(Displays.toNS(frame), display: true)
        }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        shownFrame = nil
        window.orderOut(nil)
    }
}

private struct DropHintView: View {
    let stacking: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            shape.fill(Brand.violet.opacity(0.22))
            shape.strokeBorder(Brand.violet.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            Label(stacking ? "Add to this stack" : "Swap", systemImage: stacking ? "square.stack.3d.up.fill" : "arrow.left.arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassSurface(Capsule())
        }
        .padding(4)
    }
}

// MARK: - Notices ("Maximum size reached", "3 windows on this screen")

final class NoticeHUD {
    private let window = makeOverlayWindow(level: .statusBar)
    private let host = NSHostingView(rootView: NoticeView(text: "", symbol: "checkmark"))
    private var hideWork: DispatchWorkItem?

    init() { window.contentView = host }

    func show(_ text: String, symbol: String, on d: Display?) {
        host.rootView = NoticeView(text: text, symbol: symbol)
        let size = host.fittingSize
        let vf = d.map { Displays.toNS($0.visible) } ?? NSScreen.main?.visibleFrame ?? .zero
        window.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.minY + 70, width: size.width, height: size.height), display: true)
        hideWork?.cancel()
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.window.alphaValue == 0 { self?.window.orderOut(nil) }
            })
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: w)
    }
}

private struct NoticeView: View {
    let text: String
    let symbol: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.violet)
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .glassSurface(Capsule())
        .padding(10)
        .fixedSize()
    }
}
#endif
