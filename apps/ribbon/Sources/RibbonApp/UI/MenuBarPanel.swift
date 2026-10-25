#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import RibbonCore

/// The menu bar icon and the panel it opens: the place to arrange windows with clicks. A live map of
/// the screen, a gallery of layouts, buttons for the window in use and the switches for every mode.
final class MenuBarController: NSObject, NSWindowDelegate {
    private var item: NSStatusItem?
    private var panel: KeyPanel?
    let model = PanelModel()
    private var outsideMonitor: Any?

    var isOpen: Bool { panel?.isVisible == true }
    var statusButtonFrame: NSRect? { item?.button?.window?.frame }

    func install() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.target = self
        it.button?.action = #selector(toggle)
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        it.button?.toolTip = "Ribbon: arrange windows"
        it.button?.setAccessibilityLabel("Ribbon window layouts")
        item = it
        refresh()
    }

    func refresh() {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        let paused = !c.tilingEnabled || !wm.isRunning
        let kind = wm.commandKey().map { wm.layoutKind($0) } ?? c.layout
        let symbol: String
        if paused {
            symbol = "pause.rectangle"
        } else if !wm.cleanSpace.isEmpty {
            symbol = "rectangle.inset.filled"
        } else {
            symbol = kind == .grid ? "square.grid.2x2" : (kind == .columns ? "rectangle.split.3x1" : "arrow.left.and.right.square")
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ribbon")
        img?.isTemplate = true
        item?.button?.image = img
        item?.button?.appearsDisabled = paused
        if isOpen { model.reload() }
    }

    @objc private func toggle() {
        if isOpen { close() } else { open() }
    }

    /// ⌃⌥Space: the one shortcut to remember. The panel then also answers single keys.
    func toggleFromKeyboard() {
        if isOpen { close() } else { open(fromKeyboard: true) }
    }

    func open(fromKeyboard: Bool = false) {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { model.frontApp = front }
        model.keyboard = fromKeyboard
        model.key = nil
        model.reload()
        let hc = NSHostingController(rootView: PanelView(model: model) { [weak self] in self?.close() })
        hc.sizingOptions = [.preferredContentSize]
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 640), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentViewController = hc
        p.onEscape = { [weak self] in self?.close() }
        p.onKeyEvent = { [weak self] e in self?.key(e) ?? false }
        p.delegate = self
        p.setAccessibilityLabel("Ribbon")
        panel?.orderOut(nil)
        panel = p
        position()
        // A non-activating panel takes clicks and keys without pulling focus from the app you were in.
        p.makeKeyAndOrderFront(nil)
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        }
    }

    func close() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func windowDidResize(_ notification: Notification) { position() }

    /// Hangs the panel from the menu bar icon, kept on screen.
    private func position() {
        guard let p = panel else { return }
        let size = p.frame.size
        let anchor = item?.button?.window?.frame ?? NSRect(x: (NSScreen.main?.frame.maxX ?? 1440) - 200, y: (NSScreen.main?.frame.maxY ?? 900) - 24,
                                                          width: 24, height: 24)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
        let x = min(max(vf.minX + 8, anchor.midX - size.width / 2), vf.maxX - size.width - 8)
        p.setFrameTopLeftPoint(NSPoint(x: x, y: min(anchor.minY - 4, vf.maxY)))
    }

    /// Single keys while the panel is open: 1–4 windows, G C S layouts, arrows swap, ↩ main, and so on.
    private func key(_ e: NSEvent) -> Bool {
        let wm = WindowManager.shared
        guard let key = model.screenKey, let d = wm.display(uuid: key.display) else { return false }
        let ch = (e.charactersIgnoringModifiers ?? "").lowercased()
        switch e.keyCode {
        case 123: model.act(.swapLeft)
        case 124: model.act(.swapRight)
        case 125: model.act(.swapDown)
        case 126: model.act(.swapUp)
        case 36, 76: model.act(.makePrimary)
        default:
            switch ch {
            case "1", "2", "3", "4":
                let kind = wm.layoutKind(key) == .scrolling ? LayoutKind.grid : wm.layoutKind(key)
                wm.setArrangement(kind, count: Int(ch) ?? 3, for: key)
            case "g": wm.setArrangement(.grid, count: wm.capacity(key, d), for: key)
            case "c": wm.setArrangement(.columns, count: max(2, wm.capacity(key, d)), for: key)
            case "s": wm.setArrangement(.scrolling, count: 99, for: key)
            case "f": model.act(.toggleFloat)
            case "z": model.act(.focusMode)
            case "d": wm.toggleNoPeek()
            case "p": wm.toggleCleanSpace()
            case "t": wm.retile()
            case "=", "+": model.act(.grow)
            case "-": model.act(.shrink)
            default: return false
            }
        }
        model.reload()
        return true
    }
}

final class PanelModel: ObservableObject {
    @Published var tick = 0
    var frontApp: NSRunningApplication?
    /// The screen the panel is showing; nil follows the window in use.
    @Published var key: ScreenKey?
    /// Opened with ⌃⌥Space, so it shows the single-key hints.
    var keyboard = false

    func reload() {
        let wm = WindowManager.shared
        if let k = key, !wm.isActive(k) { key = nil }
        tick += 1
    }

    var screenKey: ScreenKey? { key ?? WindowManager.shared.commandKey() }

    /// Runs a command on the window in use on the panel's screen.
    func act(_ c: Command) {
        let wm = WindowManager.shared
        if let k = screenKey, let (wid, _) = wm.windowInUse(k), wm.focusedWindowID != wid { wm.focusOS(wid) }
        wm.perform(c)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.reload() }
    }
}

// MARK: - The panel

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var store = SettingsStore.shared
    let close: () -> Void

    private var wm: WindowManager { WindowManager.shared }

    var body: some View {
        let _ = model.tick
        VStack(alignment: .leading, spacing: 12) {
            header
            actionCard
            if wm.isRunning, let key = model.screenKey, let d = wm.display(uuid: key.display) {
                if wm.displays.count > 1 { displayPicker(key) }
                ScreenMap(key: key, display: d, model: model)
                LayoutGallery(key: key, display: d, model: model)
                WindowCard(key: key, display: d, model: model)
                modes(key, d)
            }
            frontAppRow
            if model.keyboard { keyHints }
            footer
        }
        .padding(14)
        .frame(width: 384)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(1)
        .animation(Brand.snappy, value: model.tick)
    }

    // MARK: Header

    private var status: (Color, String) {
        if !AXPermission.isTrusted { return (.red, "Needs Accessibility access") }
        if !store.config.tilingEnabled { return (.gray, "Tiling is off") }
        if wm.pausedForStageManager { return (.orange, "Paused while Stage Manager is on") }
        if !wm.isRunning { return (.orange, "Starting…") }
        if let key = model.screenKey, wm.cleanSpace.contains(key.display) { return (.green, "Clean Space") }
        if let key = model.screenKey, wm.boards[key]?.zoomed != nil { return (.green, "Focus mode") }
        let n = wm.boards.filter { wm.isActive($0.key) }.reduce(0) { $0 + $1.value.windowCount }
        return (.green, n == 1 ? "Arranging 1 window" : "Arranging \(n) windows")
    }

    private var header: some View {
        let (color, text) = status
        return HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ribbon").font(.system(size: 14, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.6), radius: 2)
                    Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if wm.isRunning {
                Button { wm.retile(); model.reload() } label: {
                    Label("Tidy Up", systemImage: "sparkles").font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(QuietButtonStyle())
                .help("Put every window back in its place (T)")
            }
            Toggle("", isOn: Binding<Bool>(get: { store.config.tilingEnabled }, set: { store.config.tilingEnabled = $0; model.reload() }))
                .toggleStyle(.switch).labelsHidden().tint(Brand.violet)
                .help("Arrange windows automatically")
                .accessibilityLabel("Arrange windows automatically")
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        if !AXPermission.isTrusted {
            VStack(alignment: .leading, spacing: 6) {
                card("hand.raised.fill", BadgeColors.red, "Ribbon needs Accessibility access to arrange your windows.", "Grant Access") {
                    AXPermission.prompt()
                    AXPermission.openSettings()
                }
                HStack(spacing: 6) {
                    Text("Already switched on?").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Button("Fix permission") { AXPermission.repair() }.buttonStyle(.link).font(.system(size: 11.5, weight: .semibold))
                    Text("·").foregroundStyle(.tertiary)
                    Button("Relaunch") { AppInfo.relaunch() }.buttonStyle(.link).font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.leading, 4)
            }
        } else if IsSecureEventInputEnabled() {
            card("lock.fill", BadgeColors.orange, "Another app is using Secure Input, so shortcuts pause until it's done. Clicks here still work.", nil) {}
        } else if !HotkeyCenter.shared.failed.isEmpty {
            card("exclamationmark.triangle.fill", BadgeColors.orange,
                 "\(HotkeyCenter.shared.failed.count) shortcut\(HotkeyCenter.shared.failed.count == 1 ? " is" : "s are") taken by another app.",
                 "Review") { close(); UIHub.shared.openSettings(tab: SettingsPane.shortcuts.rawValue) }
        }
    }

    private func card(_ symbol: String, _ colors: [Color], _ text: String, _ button: String?, _ run: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            IconBadge(symbol: symbol, colors: colors, size: 24)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                Button(button, action: run).buttonStyle(BrandButtonStyle())
            }
        }
        .card(padding: 10, radius: 14)
    }

    private func displayPicker(_ key: ScreenKey) -> some View {
        let sorted = wm.displays.sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        return HStack(spacing: 6) {
            ForEach(sorted, id: \.uuid) { (d: Display) in
                let on = d.uuid == key.display
                Button {
                    model.key = wm.activeKey(for: d)
                    model.reload()
                } label: {
                    Label(d.name, systemImage: d.isMain ? "laptopcomputer" : "display")
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: Modes

    private func modes(_ key: ScreenKey, _ d: Display) -> some View {
        let c = store.config
        let clean = wm.cleanSpace.contains(d.uuid)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ModeTile(symbol: "eye.slash", title: "No peek", on: wm.noPeek, hint: "D") { wm.toggleNoPeek(); model.reload() }
                ModeTile(symbol: "rectangle.inset.filled", title: "Clean Space", on: clean, hint: "P") { wm.toggleCleanSpace(); model.reload() }
                ModeTile(symbol: "square.dashed", title: "Borders", on: c.highlight != .none, hint: nil) {
                    store.config.highlight = c.highlight == .none ? .activeBorder : .none
                }
                ModeTile(symbol: "cursorarrow.motionlines", title: "Hover focus", on: c.hoverFocus, hint: nil) { store.config.hoverFocus.toggle() }
            }
            if wm.noPeek {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: Binding<Double>(get: { store.config.noPeekDim }, set: { store.config.noPeekDim = $0 }), in: 0.1...0.9)
                        .tint(Brand.violet)
                        .accessibilityLabel("How dark the other windows get")
                    Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var frontAppRow: some View {
        if let app = model.frontApp, let bid = app.bundleIdentifier, wm.isRunning {
            let name = app.localizedName ?? bid
            HStack(spacing: 10) {
                Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                Text("Tile \(name)").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding<Bool>(get: { store.config.tiles(bid) }, set: { wm.setAppTiles($0, bundleID: bid, name: name) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Brand.violet)
                    .accessibilityLabel("Tile \(name)'s windows")
            }
            .help("Off leaves \(name)'s windows where you put them")
        }
    }

    private var keyHints: some View {
        HStack(spacing: 8) {
            hint("1–4", "windows")
            hint("G C S", "layout")
            hint("← →", "swap")
            hint("↩", "main")
            hint("esc", "close")
        }
        .frame(maxWidth: .infinity)
    }

    private func hint(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.1)))
            Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(symbol: "gearshape", title: "Settings") { close(); UIHub.shared.openSettings() }
            FooterButton(symbol: "keyboard", title: "Shortcuts") { close(); UIHub.shared.showCheatSheet() }
            FooterButton(symbol: "questionmark.circle", title: "Tour") { close(); UIHub.shared.showOnboarding(step: 0) }
            FooterButton(symbol: "power", title: "Quit") { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Live map of the screen

/// The screen as it is: click a window to switch to it, drag one onto another to swap them, rest on
/// one for quick buttons.
struct ScreenMap: View {
    let key: ScreenKey
    let display: Display
    @ObservedObject var model: PanelModel

    var body: some View {
        let wm = WindowManager.shared
        let b = wm.boards[key] ?? Board()
        let frames = wm.tileFrames[key] ?? []
        let d = display.frame
        let aspect = CGFloat(d.w / max(1, d.h))
        let scrolling = wm.isScrolling(key)
        let leftOff = scrolling ? frames.filter { $0.maxX <= d.x + 1 }.count : 0
        let rightOff = scrolling ? frames.filter { $0.minX >= d.maxX - 1 }.count : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.isEmpty ? "This screen" : "This screen · click to switch, drag to swap")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !b.splits.isDefault || b.tiles.contains(where: { $0.width != nil }) {
                    Button {
                        wm.resetSizes(key)
                        model.reload()
                    } label: {
                        Label("Equal sizes", systemImage: "arrow.uturn.backward").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Brand.violet)
                }
            }
            GeometryReader { geo in
                let k = geo.size.width / CGFloat(d.w)
                ZStack(alignment: .topLeading) {
                    Wallpaper().opacity(0.9)
                    if b.isEmpty {
                        Text("Open a window and it appears here").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ForEach(Array(b.tiles.enumerated()), id: \.element.showing) { (pair: (offset: Int, element: Tile)) in
                        let i = pair.offset
                        let t = pair.element
                        if frames.indices.contains(i), b.zoomed == nil || b.zoomed == t.showing,
                           let f = clip(b.zoomed == t.showing ? wm.area(for: display) : frames[i], to: d) {
                            MapTile(tile: t, active: t.showing == (wm.windowInUse(key)?.0), model: model)
                                .frame(width: max(18, CGFloat(f.w) * k - 3), height: max(14, CGFloat(f.h) * k - 3))
                                .offset(x: CGFloat(f.x - d.x) * k + 1.5, y: CGFloat(f.y - d.y) * k + 1.5)
                        }
                    }
                    if leftOff > 0 { offscreen(leftOff, left: true) }
                    if rightOff > 0 { offscreen(rightOff, left: false).frame(maxWidth: .infinity, alignment: .trailing) }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .frame(maxHeight: 210)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Windows on this screen")
        }
    }

    private func clip(_ f: Rect, to d: Rect) -> Rect? {
        guard let r = f.intersection(d), r.w > 6 else { return nil }
        return r
    }

    /// Scrolling layout: windows scrolled out of view, one click away.
    private func offscreen(_ n: Int, left: Bool) -> some View {
        Button { model.act(left ? .focusPrevious : .focusNext) } label: {
            HStack(spacing: 3) {
                if left { Image(systemName: "chevron.left") }
                Text("\(n)")
                if !left { Image(systemName: "chevron.right") }
            }
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .padding(6)
        .frame(maxHeight: .infinity)
        .accessibilityLabel("\(n) more window\(n == 1 ? "" : "s") to the \(left ? "left" : "right")")
    }
}

private struct MapTile: View {
    let tile: Tile
    let active: Bool
    @ObservedObject var model: PanelModel
    @State private var hover = false
    @State private var target = false

    var body: some View {
        let wm = WindowManager.shared
        let w = wm.windows[tile.showing]
        let name = w?.appName ?? "Window"
        let title = w?.title ?? ""
        return GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(target ? 0.7 : 0.94))
                VStack(spacing: 3) {
                    if let pid = w?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: min(26, geo.size.height * 0.45), height: min(26, geo.size.height * 0.45))
                    }
                    if geo.size.height > 52 && geo.size.width > 60 {
                        Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 4)
                    }
                }
                if tile.isStack {
                    Text("\(tile.windows.count)").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .accessibilityHidden(true)
                }
                if hover && geo.size.width > 70 && geo.size.height > 40 {
                    HStack(spacing: 3) {
                        mini("crown.fill", "Make main") { switchTo(); model.act(.makePrimary) }
                        mini("scope", "Focus: fill the screen") { switchTo(); model.act(.focusMode) }
                        mini("macwindow.on.rectangle", "Float") { switchTo(); model.act(.toggleFloat) }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(target ? Brand.rose : (active ? Brand.violet : Color.clear), lineWidth: target ? 2.5 : 2))
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { switchTo(); model.reload() }
        .onDrag { NSItemProvider(object: String(tile.showing) as NSString) }
        .onDrop(of: [UTType.plainText], isTargeted: $target) { providers in
            guard let p = providers.first else { return false }
            let me = tile.showing
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? NSString, let other = WindowID(s as String) else { return }
                DispatchQueue.main.async {
                    WindowManager.shared.swapWindows(other, me)
                    model.reload()
                }
            }
            return true
        }
        .help(title.isEmpty ? name : "\(name): \(title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? name : "\(name), \(title)")
        .accessibilityHint("Switches to this window. Drag it onto another window to swap them.")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Make main") { switchTo(); model.act(.makePrimary) }
        .accessibilityAction(named: "Focus") { switchTo(); model.act(.focusMode) }
        .accessibilityAction(named: "Float") { switchTo(); model.act(.toggleFloat) }
    }

    private func switchTo() { WindowManager.shared.focus(window: tile.showing) }

    private func mini(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.violet))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Layout gallery

struct LayoutChoice: Identifiable, Equatable {
    let id: String
    let kind: LayoutKind
    let count: Int
    let title: String
    let detail: String

    static let all: [LayoutChoice] = [
        LayoutChoice(id: "full", kind: .grid, count: 1, title: "Full", detail: "One window fills the screen; others stack behind it"),
        LayoutChoice(id: "halves", kind: .grid, count: 2, title: "Halves", detail: "Two windows side by side"),
        LayoutChoice(id: "main2", kind: .grid, count: 3, title: "1 + 2", detail: "A main window on the left, two on the right"),
        LayoutChoice(id: "quarters", kind: .grid, count: 4, title: "Quarters", detail: "Four windows in a grid"),
        LayoutChoice(id: "cols3", kind: .columns, count: 3, title: "3 columns", detail: "Three full-height columns"),
        LayoutChoice(id: "cols4", kind: .columns, count: 4, title: "4 columns", detail: "Four full-height columns, for wide screens"),
        LayoutChoice(id: "scroll", kind: .scrolling, count: 99, title: "Scrolling", detail: "Columns that run past the screen; swipe or ⌃⌥ + scroll"),
    ]
}

struct LayoutGallery: View {
    let key: ScreenKey
    let display: Display
    @ObservedObject var model: PanelModel

    var body: some View {
        let wm = WindowManager.shared
        let kind = wm.layoutKind(key)
        let cap = wm.capacity(key, display)
        let maxCols = TileLayout.maxTiles(.columns, area: wm.area(for: display))
        let current = LayoutChoice.all.first { c in
            if kind == .scrolling { return c.kind == .scrolling }
            if cap <= 2 { return c.count == cap && c.kind == .grid }
            return c.kind == kind && c.count == cap
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Layout").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(current?.detail ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 4) {
                ForEach(LayoutChoice.all) { (c: LayoutChoice) in
                    let disabled = c.kind == .columns && c.count > maxCols
                    let on = c == current
                    Button {
                        wm.setArrangement(c.kind, count: c.count, for: key)
                        model.reload()
                    } label: {
                        VStack(spacing: 4) {
                            LayoutGlyph(kind: c.kind, count: c.count, on: on)
                                .frame(width: 36, height: 24)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(on ? 0 : 0.08)))
                                .shadow(color: Brand.violet.opacity(on ? 0.35 : 0), radius: 5, y: 2)
                            Text(c.title).font(.system(size: 9.5, weight: on ? .bold : .medium)).lineLimit(1)
                                .foregroundStyle(on ? Color.primary : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(disabled)
                    .opacity(disabled ? 0.35 : 1)
                    .help(disabled ? "\(c.detail). This screen fits up to \(maxCols) columns." : c.detail)
                    .accessibilityLabel("\(c.title) layout")
                    .accessibilityHint(c.detail)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// A tiny picture of a layout.
struct LayoutGlyph: View {
    let kind: LayoutKind
    let count: Int
    var on = false

    var body: some View {
        Canvas { ctx, size in
            let area = Rect(x: 0, y: 0, w: Double(size.width), h: Double(size.height))
            var frames: [Rect]
            if kind == .scrolling {
                let w = area.w * 0.42
                let mid = area.w / 2 - w / 2
                frames = [Rect(x: mid, y: 0, w: w, h: area.h), Rect(x: mid - w - 2.5, y: 0, w: w, h: area.h),
                          Rect(x: mid + w + 2.5, y: 0, w: w, h: area.h)]
            } else {
                frames = TileLayout.frames(count: count, kind == .columns ? .columns : .grid, area: area, gap: 2.5, splits: Splits())
            }
            let main: Color = on ? .white : Color.primary.opacity(0.55)
            let rest: Color = on ? Color.white.opacity(0.6) : Color.primary.opacity(0.28)
            for (i, f) in frames.enumerated() {
                let r = CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(i == 0 ? main : rest))
            }
            if kind == .scrolling {
                // Arrows hinting that the strip runs past the edges.
                let y = size.height / 2
                var l = Path()
                l.move(to: CGPoint(x: 5, y: y - 4)); l.addLine(to: CGPoint(x: 1.5, y: y)); l.addLine(to: CGPoint(x: 5, y: y + 4))
                var r = Path()
                r.move(to: CGPoint(x: size.width - 5, y: y - 4)); r.addLine(to: CGPoint(x: size.width - 1.5, y: y))
                r.addLine(to: CGPoint(x: size.width - 5, y: y + 4))
                let ink: Color = on ? Brand.indigo : Color.primary.opacity(0.7)
                ctx.stroke(l, with: .color(ink), lineWidth: 1.6)
                ctx.stroke(r, with: .color(ink), lineWidth: 1.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - The window in use

struct WindowCard: View {
    static let widths: [(value: Double, label: String)] = [(1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (1.0, "Full")]
    let key: ScreenKey
    let display: Display
    @ObservedObject var model: PanelModel

    var body: some View {
        let wm = WindowManager.shared
        let inUse = wm.windowInUse(key)
        let w = inUse.flatMap { wm.windows[$0.0] }
        let scrolling = wm.isScrolling(key)
        let b = wm.boards[key] ?? Board()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let pid = w?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(w?.appName ?? "No window yet").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if let t = w?.title, !t.isEmpty {
                        Text(t).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                if b.zoomed != nil { StatusPill(kind: .info, text: "Focus") }
            }
            HStack(spacing: 6) {
                ActionButton(symbol: "arrow.left", title: "Swap", hint: "⌃⌥←", cmd: .swapLeft, model: model)
                ActionButton(symbol: "arrow.right", title: "Swap", hint: "⌃⌥→", cmd: .swapRight, model: model)
                if !scrolling {
                    ActionButton(symbol: "arrow.up", title: "Swap", hint: "⌃⌥↑", cmd: .swapUp, model: model)
                    ActionButton(symbol: "arrow.down", title: "Swap", hint: "⌃⌥↓", cmd: .swapDown, model: model)
                }
                Divider().frame(height: 30)
                ActionButton(symbol: "crown.fill", title: "Main", hint: "⌃⌥↩", cmd: .makePrimary, model: model)
                ActionButton(symbol: "scope", title: "Focus", hint: "⌃⌥Z", cmd: .focusMode, model: model, on: b.zoomed != nil)
                ActionButton(symbol: "macwindow.on.rectangle", title: "Float", hint: "⌃⌥F", cmd: .toggleFloat, model: model)
                if scrolling {
                    ActionButton(symbol: "arrow.left.and.right", title: "Width", hint: "⌃⌥R", cmd: .cycleWidth, model: model)
                }
            }
            HStack(spacing: 6) {
                if scrolling, let (_, i) = inUse {
                    ForEach(WindowCard.widths, id: \.label) { (p: (value: Double, label: String)) in
                        let current = b.tiles.indices.contains(i) ? (b.tiles[i].width ?? SettingsStore.shared.config.scrollingWidth) : 0
                        WidthButton(label: p.label, on: abs(current - p.value) < 0.01) {
                            wm.setWidth(p.value, tile: i, key: key)
                            model.reload()
                        }
                    }
                } else {
                    ActionButton(symbol: "plus.magnifyingglass", title: "Bigger", hint: "⌃⌥=", cmd: .grow, model: model, compact: true)
                    ActionButton(symbol: "minus.magnifyingglass", title: "Smaller", hint: "⌃⌥−", cmd: .shrink, model: model, compact: true)
                }
                if wm.displays.count > 1 {
                    ActionButton(symbol: "display.2", title: "Next screen", hint: nil, cmd: .nextDisplay, model: model, compact: true)
                }
                if b.tiles.contains(where: { $0.isStack }) {
                    ActionButton(symbol: "square.stack.3d.up", title: "Next in stack", hint: "⌃⌥`", cmd: .stackNext, model: model, compact: true)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .disabled(inUse == nil)
        .opacity(inUse == nil ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The window you're using")
    }
}

/// A round icon button with a caption; the tooltip shows its shortcut.
private struct ActionButton: View {
    let symbol: String
    let title: String
    let hint: String?
    let cmd: Command
    @ObservedObject var model: PanelModel
    var on = false
    var compact = false
    @State private var hover = false

    var body: some View {
        Button { model.act(cmd) } label: {
            Group {
                if compact {
                    Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Capsule().fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(hover ? 0.12 : 0.07))))
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 28)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(hover ? 0.13 : 0.07))))
                        Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(hint.map { "\(cmd.title) (\($0))" } ?? cmd.title)
        .accessibilityLabel(cmd.title)
    }
}

private struct WidthButton: View {
    let label: String
    let on: Bool
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(minWidth: 34, minHeight: 26)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(PressableStyle())
        .help("Column width: \(label == "Full" ? "the whole screen" : label + " of the screen")")
        .accessibilityLabel(label == "Full" ? "Full width" : "\(label) width")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct ModeTile: View {
    let symbol: String
    let title: String
    let on: Bool
    let hint: String?
    let run: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(hover ? 0.11 : 0.06))))
            .foregroundStyle(on ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(hint.map { "\(title) (\($0) while this panel is open)" } ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String
    let run: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hover ? 0.09 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Buttons that dip slightly when pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Brand.snappy, value: configuration.isPressed)
    }
}
#endif
