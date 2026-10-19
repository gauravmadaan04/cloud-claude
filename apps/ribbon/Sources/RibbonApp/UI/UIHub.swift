#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// Owns every piece of Ribbon's own UI and keeps it in step with the window manager.
final class UIHub {
    static let shared = UIHub()

    let statusMenu = StatusMenuController()
    let overlays = FocusOverlays()
    let indicator = StripIndicatorController()
    let tabBars = TabBarController()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cheatSheet: NSPanel?
    private var refreshPending = false
    let settingsNav = SettingsNavigation()

    func setup() {
        let wm = WindowManager.shared
        statusMenu.install()
        wm.layoutListeners.append { [weak self] in self?.scheduleRefresh() }
        wm.frameListeners.append { [weak self] wid, f in
            self?.overlays.windowMoved(wid, frame: f)
            self?.tabBars.windowMoved(wid, frame: f)
        }
        wm.runningListeners.append { [weak self] _ in
            self?.statusMenu.refresh()
            self?.scheduleRefresh()
        }
        SettingsStore.shared.onChange { [weak self] _, _ in
            self?.statusMenu.refresh()
            self?.scheduleRefresh()
        }
        InputMonitors.shared.onHoldChanged = { [weak self] holding in
            guard SettingsStore.shared.config.showIndicatorOnHold else { return }
            if holding { self?.indicator.show(for: wm.commandKey(), sticky: true) } else { self?.indicator.endSticky() }
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.overlays.refresh()
            self.tabBars.refresh()
            self.indicator.refresh()
            self.statusMenu.refresh()
        }
    }

    // MARK: Windows

    func openSettings(tab: String? = nil) {
        if let t = tab, let pane = SettingsPane(rawValue: t) { settingsNav.pane = pane }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ribbon Settings"
            w.titlebarAppearsTransparent = true
            w.toolbar = NSToolbar(identifier: "RibbonSettings")
            w.toolbarStyle = .unified
            w.contentViewController = NSHostingController(rootView: SettingsView(nav: settingsNav))
            w.setContentSize(NSSize(width: 900, height: 660))
            w.minSize = NSSize(width: 820, height: 560)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("RibbonSettings")
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding(step: Int? = nil) {
        if let step { OnboardingModel.shared.step = max(0, min(6, step)) }
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.title = "Welcome to Ribbon"
            w.contentViewController = NSHostingController(rootView: OnboardingView { [weak self] in self?.finishOnboarding() })
            w.setContentSize(NSSize(width: 900, height: 640))
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func finishOnboarding() {
        SettingsStore.shared.config.hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        WindowManager.shared.start()
    }

    func showCheatSheet() {
        if let c = cheatSheet, c.isVisible { c.orderOut(nil); return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(1080, vf.width - 60), height: min(680, vf.height - 60))
        // Rebuilt each time so it reflects the current shortcuts and fits the current screen.
        let panel = makeCheatSheet(size: size)
        cheatSheet?.orderOut(nil)
        cheatSheet = panel
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func makeCheatSheet(size: NSSize) -> NSPanel {
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: CheatSheetView(size: size) { [weak p] in p?.orderOut(nil) })
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        p.onEscape = { [weak p] in p?.orderOut(nil) }
        return p
    }

    func closeAppWindows() {
        settingsWindow?.close()
        onboardingWindow?.close()
        cheatSheet?.orderOut(nil)
    }

    // MARK: Strip map

    func showIndicator(for key: StripKey?, duration: Double) {
        indicator.show(for: key, sticky: false, duration: duration, interactive: true)
    }

    func flashIndicator(for key: StripKey?) {
        guard SettingsStore.shared.config.showIndicatorOnScroll else { return }
        indicator.show(for: key, sticky: false, duration: 1.1, interactive: false)
    }
}

/// A panel that can become key (so it can take Escape) without activating Ribbon.
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// A borderless, click-through window used for borders, dimming and other decoration.
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

// MARK: - Focus border and dimming

final class FocusOverlays {
    private let border = makeOverlayWindow(level: .floating)
    private let borderLayer = CAShapeLayer()
    private var dims: [WindowID: NSWindow] = [:]
    private var focused: WindowID?

    init() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.addSublayer(borderLayer)
        borderLayer.fillColor = nil
        border.contentView = v
    }

    func refresh() {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        focused = wm.focusedWindowID
        // Border
        if c.focusBorder, wm.isRunning, let f = focused, let w = wm.windows[f], w.key != nil, let frame = w.lastFrame,
           isOnScreen(f) {
            borderLayer.strokeColor = (NSColor(hex: c.borderColor) ?? .systemBlue).cgColor
            borderLayer.lineWidth = c.borderWidth
            place(frame)
            border.orderFrontRegardless()
        } else {
            border.orderOut(nil)
        }
        // Dimming
        var keep = Set<WindowID>()
        if c.dimUnfocused, wm.isRunning {
            for (key, r) in wm.layouts where wm.isActive(key) {
                for pl in r.placements where pl.window != focused && pl.visibility.isOnScreen {
                    guard let w = wm.windows[pl.window], let frame = w.lastFrame else { continue }
                    keep.insert(pl.window)
                    let d = dims[pl.window] ?? makeDim()
                    dims[pl.window] = d
                    d.backgroundColor = NSColor.black.withAlphaComponent(c.dimAmount)
                    d.setFrame(Displays.toNS(frame), display: false)
                    d.order(.above, relativeTo: Int(pl.window))
                }
            }
        }
        for (wid, d) in dims where !keep.contains(wid) {
            d.orderOut(nil)
            dims[wid] = nil
        }
    }

    private func isOnScreen(_ wid: WindowID) -> Bool {
        let wm = WindowManager.shared
        for (key, r) in wm.layouts where wm.isActive(key) {
            if let pl = r.placement(for: wid) { return pl.visibility.isOnScreen }
        }
        return false
    }

    private func makeDim() -> NSWindow {
        let w = makeOverlayWindow(level: .normal)
        w.contentView = NSView()
        return w
    }

    private func place(_ frame: Rect) {
        let c = SettingsStore.shared.config
        let inset = c.borderWidth / 2
        let ns = Displays.toNS(frame).insetBy(dx: -c.borderWidth, dy: -c.borderWidth)
        border.setFrame(ns, display: false)
        let bounds = CGRect(origin: .zero, size: ns.size).insetBy(dx: inset, dy: inset)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.frame = CGRect(origin: .zero, size: ns.size)
        borderLayer.path = CGPath(roundedRect: bounds, cornerWidth: c.borderRadius + inset, cornerHeight: c.borderRadius + inset, transform: nil)
        CATransaction.commit()
    }

    func windowMoved(_ wid: WindowID, frame: Rect) {
        if wid == focused, border.isVisible { place(frame) }
        if let d = dims[wid] { d.setFrame(Displays.toNS(frame), display: false) }
    }
}

// MARK: - Tab bars for tabbed columns

final class TabBarController {
    private final class Bar {
        let panel: NSPanel
        let model = TabBarModel()
        var windows: [WindowID] = []
        init() {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: TabBarView(model: model))
        }
    }

    private var bars: [UUID: Bar] = [:]
    private var byWindow: [WindowID: UUID] = [:]

    func refresh() {
        let wm = WindowManager.shared
        var keep = Set<UUID>()
        byWindow.removeAll()
        if wm.isRunning {
            for (key, r) in wm.layouts where wm.isActive(key) {
                guard let s = wm.strips[key] else { continue }
                for tb in r.tabBars where s.columns.indices.contains(tb.column) {
                    let col = s.columns[tb.column]
                    guard r.columnVisibility.indices.contains(tb.column), r.columnVisibility[tb.column].isOnScreen else { continue }
                    keep.insert(col.id)
                    let bar = bars[col.id] ?? Bar()
                    bars[col.id] = bar
                    bar.windows = tb.windows
                    bar.model.tabs = tb.windows.map { wid in
                        let w = wm.windows[wid]
                        return TabBarModel.Tab(id: wid, title: (w?.title.isEmpty ?? true) ? (w?.appName ?? "Window") : w!.title,
                                               icon: w.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon })
                    }
                    bar.model.active = tb.active
                    bar.model.focused = tb.windows.contains(wm.focusedWindowID ?? 0)
                    for wid in tb.windows { byWindow[wid] = col.id }
                    let x = wm.windows[tb.windows[tb.active]]?.lastFrame?.x ?? tb.frame.x
                    bar.panel.setFrame(Displays.toNS(Rect(x: x, y: tb.frame.y, w: tb.frame.w, h: tb.frame.h - 2)), display: true)
                    bar.panel.orderFrontRegardless()
                }
            }
        }
        for (id, bar) in bars where !keep.contains(id) {
            bar.panel.orderOut(nil)
            bars[id] = nil
        }
    }

    func windowMoved(_ wid: WindowID, frame: Rect) {
        guard let id = byWindow[wid], let bar = bars[id], bar.windows.firstIndex(of: wid) == bar.model.active else { return }
        var f = bar.panel.frame
        f.origin.x = frame.x
        bar.panel.setFrame(f, display: false)
    }
}

final class TabBarModel: ObservableObject {
    struct Tab: Identifiable {
        let id: WindowID
        let title: String
        let icon: NSImage?
    }
    @Published var tabs: [Tab] = []
    @Published var active = 0
    @Published var focused = false
}

struct TabBarView: View {
    @ObservedObject var model: TabBarModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { i, tab in
                tabButton(i, tab)
            }
        }
        .padding(3)
        .glassSurface(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func tabButton(_ i: Int, _ tab: TabBarModel.Tab) -> some View {
        let active = i == model.active
        return Button {
            WindowManager.shared.focus(window: tab.id)
        } label: {
            HStack(spacing: 6) {
                if let icon = tab.icon { Image(nsImage: icon).resizable().frame(width: 15, height: 15) }
                Text(tab.title).lineLimit(1).truncationMode(.middle)
                    .font(.system(size: 12, weight: active ? Font.Weight.semibold : Font.Weight.regular))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                    .opacity(active && !model.focused ? 0.6 : 1)
            )
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cheat sheet

extension Command.Category {
    var badge: (symbol: String, colors: [Color]) {
        switch self {
        case .focus: return ("scope", BadgeColors.blue)
        case .move: return ("arrow.left.arrow.right", BadgeColors.indigo)
        case .size: return ("arrow.left.and.right.square", BadgeColors.teal)
        case .stacks: return ("square.stack.fill", BadgeColors.pink)
        case .other: return ("slider.horizontal.3", BadgeColors.gray)
        }
    }
}

struct CheatSheetView: View {
    let size: NSSize
    var close: () -> Void
    @ObservedObject private var store = SettingsStore.shared
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns().indices, id: \.self) { ci in
                        VStack(spacing: 14) {
                            ForEach(columns()[ci], id: \.self) { cat in categoryCard(cat) }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(18)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: size.width, height: size.height)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), material: .regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .tint(Brand.violet)
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "keyboard.fill", colors: BadgeColors.brand, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Shortcuts").font(.system(size: 20, weight: .bold))
                Text("Everything Ribbon can do from the keyboard").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain).frame(width: 170)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint(["⌃", "⌥"], "Hold to see the strip map")
            hint(["esc"], "Close")
            Spacer()
            Button("Customise in Settings…") {
                close()
                UIHub.shared.openSettings(tab: SettingsPane.shortcuts.rawValue)
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func hint(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { KeyCap(label: $0, size: .small) }
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func categoryCard(_ cat: Command.Category) -> some View {
        let cmds = commands(in: cat)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                IconBadge(symbol: cat.badge.symbol, colors: cat.badge.colors, size: 22)
                Text(cat.rawValue).font(.system(size: 13, weight: .bold))
            }
            .padding(.bottom, 2)
            ForEach(cmds, id: \.self) { (cmd: Command) in
                HStack(spacing: 8) {
                    Text(cmd == .focus1 ? "Jump to window 1–9" : cmd.title).font(.system(size: 12.5))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    Spacer(minLength: 6)
                    if let combo = store.config.combos(for: cmd).first {
                        ShortcutKeys(combo: combo, size: .small)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .opacity(cmds.isEmpty ? 0 : 1)
    }

    /// Splits categories into balanced columns by number of rows.
    private func columns() -> [[Command.Category]] {
        let n = size.width >= 880 ? 3 : 2
        var cols = Array(repeating: [Command.Category](), count: n)
        var heights = Array(repeating: 0, count: n)
        for cat in Command.Category.allCases where !commands(in: cat).isEmpty {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            cols[i].append(cat)
            heights[i] += commands(in: cat).count + 2
        }
        return cols
    }

    private func commands(in cat: Command.Category) -> [Command] {
        Command.allCases.filter { c in
            c.category == cat && !store.config.combos(for: c).isEmpty && (c.focusIndex == nil || c == .focus1)
                && (query.isEmpty || c.title.localizedCaseInsensitiveContains(query))
        }
    }
}
#endif
