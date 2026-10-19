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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ribbon Settings"
            w.contentViewController = NSHostingController(rootView: SettingsView(nav: settingsNav))
            w.setContentSize(NSSize(width: 820, height: 600))
            w.minSize = NSSize(width: 720, height: 480)
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.title = "Welcome to Ribbon"
            w.contentViewController = NSHostingController(rootView: OnboardingView { [weak self] in self?.finishOnboarding() })
            w.setContentSize(NSSize(width: 760, height: 560))
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
        let panel = cheatSheet ?? makeCheatSheet()
        cheatSheet = panel
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makeCheatSheet() -> NSPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow, .utilityWindow],
                         backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentViewController = NSHostingController(rootView: CheatSheetView { [weak p] in p?.orderOut(nil) })
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
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { i, tab in
                Button {
                    WindowManager.shared.focus(window: tab.id)
                } label: {
                    HStack(spacing: 6) {
                        if let icon = tab.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                        Text(tab.title).lineLimit(1).truncationMode(.middle).font(.system(size: 12, weight: i == model.active ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(i == model.active ? Color.accentColor.opacity(model.focused ? 0.9 : 0.45) : Color.primary.opacity(0.06))
                    )
                    .foregroundColor(i == model.active ? .white : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }
}

// MARK: - Cheat sheet

struct CheatSheetView: View {
    var close: () -> Void
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "rectangle.split.3x1").font(.title2).foregroundColor(.accentColor)
                Text("Ribbon shortcuts").font(.title2.bold())
                Spacer()
                Text("Hold ⌃⌥ to see the strip  ·  Esc to close").foregroundColor(.secondary).font(.callout)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 18) {
                    ForEach(Command.Category.allCases, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cat.rawValue.uppercased()).font(.caption.bold()).foregroundColor(.secondary)
                            ForEach(commands(in: cat), id: \.self) { cmd in
                                HStack {
                                    Text(cmd.title).font(.callout)
                                    Spacer()
                                    Text(store.config.combos(for: cmd).map { KeyboardLayout.label($0) }.joined(separator: "  "))
                                        .font(.system(.callout, design: .rounded).weight(.medium))
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 860, height: 560)
    }

    private func commands(in cat: Command.Category) -> [Command] {
        Command.allCases.filter { c in
            c.category == cat && !store.config.combos(for: c).isEmpty && (c.focusIndex == nil || c == .focus1)
        }
    }
}
#endif
