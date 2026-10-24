#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// Owns every piece of Ribbon's own UI and keeps it in step with the window manager.
final class UIHub {
    static let shared = UIHub()

    let menuBar = MenuBarController()
    let highlights = HighlightOverlays()
    let noPeek = NoPeekOverlays()
    let backdrops = CleanSpaceBackdrops()
    let grips = GripController()
    let dropHint = DropHint()
    let notices = NoticeHUD()
    let tabView = TabViewController()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cheatSheet: NSPanel?
    private var refreshPending = false
    let settingsNav = SettingsNavigation()

    func setup() {
        let wm = WindowManager.shared
        menuBar.install()
        wm.layoutListeners.append { [weak self] in self?.scheduleRefresh() }
        wm.frameListeners.append { [weak self] wid, f in self?.highlights.windowMoved(wid, frame: f) }
        wm.runningListeners.append { [weak self] _ in self?.scheduleRefresh() }
        SettingsStore.shared.onChange { [weak self] _, _ in self?.scheduleRefresh() }
        // Focus changes reorder the shading and borders as soon as macOS reports them.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.scheduleRefresh() }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.backdrops.refresh()
            self.noPeek.refresh()
            self.highlights.refresh()
            self.grips.refresh()
            self.menuBar.refresh()
        }
    }

    func notice(_ text: String, symbol: String, on d: Display?) {
        notices.show(text, symbol: symbol, on: d)
    }

    // MARK: Windows

    func openSettings(tab: String? = nil) {
        if let t = tab, let pane = SettingsPane(rawValue: t) { settingsNav.pane = pane }
        menuBar.close()
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ribbon Settings"
            w.titlebarAppearsTransparent = true
            w.toolbar = NSToolbar(identifier: "RibbonSettings")
            w.toolbarStyle = .unified
            w.contentViewController = NSHostingController(rootView: SettingsView(nav: settingsNav))
            w.setContentSize(NSSize(width: 860, height: 620))
            w.minSize = NSSize(width: 780, height: 540)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("RibbonSettings2")
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding(step: Int? = nil) {
        if let step { OnboardingModel.shared.go(max(0, min(OnboardingModel.stepCount - 1, step)), animated: false) }
        menuBar.close()
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.title = "Welcome to Ribbon"
            w.contentViewController = NSHostingController(rootView: OnboardingView { [weak self] in self?.finishOnboarding() })
            w.setContentSize(NSSize(width: 880, height: 620))
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// "Tidy My Workspace": the tour closes into the menu bar and the windows fall into place.
    func finishOnboarding() {
        SettingsStore.shared.config.hasCompletedOnboarding = true
        if let w = onboardingWindow, let button = menuBar.statusButtonFrame {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                w.animator().setFrame(button, display: true)
                w.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            })
        } else {
            onboardingWindow?.close()
            onboardingWindow = nil
        }
        let wm = WindowManager.shared
        if wm.isRunning { wm.retile() } else { wm.start(); wm.haptic() }
    }

    func showCheatSheet() {
        if let c = cheatSheet, c.isVisible { c.orderOut(nil); return }
        menuBar.close()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(1000, vf.width - 60), height: min(640, vf.height - 60))
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
        menuBar.close()
        tabView.close()
    }
}

/// A panel that can become key (so it can take Escape and arrows) without activating Ribbon.
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// Return true to swallow the key.
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }
        if let onKey, onKey(event.keyCode, event.modifierFlags) { return }
        super.keyDown(with: event)
    }
}

extension Command.Category {
    var badge: (symbol: String, colors: [Color]) {
        switch self {
        case .move: return ("arrow.left.arrow.right", BadgeColors.indigo)
        case .activate: return ("cursorarrow.click.2", BadgeColors.blue)
        case .size: return ("arrow.up.left.and.arrow.down.right", BadgeColors.teal)
        case .modes: return ("sparkles", BadgeColors.pink)
        case .layout: return ("square.grid.2x2.fill", BadgeColors.violet)
        case .app: return ("slider.horizontal.3", BadgeColors.gray)
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
                            if ci == mouseColumn() && showMouse { mouseCard }
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
            hint(["⌥", "⇥"], "Switch windows")
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
                    Text(cmd.title).font(.system(size: 12.5))
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

    private static let mouseActions: [(String, String)] = [
        ("⌘ + drag a title bar onto a window", "Swap the two"),
        ("⌥⌘ + drag onto a window", "Add to its stack"),
        ("Drag the edge between windows", "Resize; neighbours make room"),
        ("Drag onto another screen", "Move it there"),
        ("Rest on the grip above a window", "Quick actions"),
    ]

    private var showMouse: Bool {
        query.isEmpty || CheatSheetView.mouseActions.contains { "\($0.0) \($0.1)".localizedCaseInsensitiveContains(query) }
    }

    private var mouseCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                IconBadge(symbol: "computermouse.fill", colors: BadgeColors.orange, size: 22)
                Text("Mouse").font(.system(size: 13, weight: .bold))
            }
            .padding(.bottom, 2)
            ForEach(CheatSheetView.mouseActions, id: \.0) { (pair: (String, String)) in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.0).font(.system(size: 12.5, weight: .medium))
                    Text(pair.1).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    /// The column with the most room left gets the mouse card.
    private func mouseColumn() -> Int {
        let cols = columns()
        let heights = cols.map { $0.reduce(0) { $0 + commands(in: $1).count + 2 } }
        return heights.indices.min { heights[$0] < heights[$1] } ?? 0
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
            c.category == cat && !store.config.combos(for: c).isEmpty
                && (query.isEmpty || c.title.localizedCaseInsensitiveContains(query))
        }
    }
}
#endif
