#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import RibbonCore

/// The menu bar icon and the panel it opens: status, this screen's layout and the quick switches.
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
        it.button?.toolTip = "Ribbon"
        item = it
        refresh()
    }

    func refresh() {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        let paused = !c.tilingEnabled || !wm.isRunning
        let symbol = paused ? "pause.rectangle" : (wm.cleanSpace.isEmpty ? "square.grid.2x2" : "rectangle.inset.filled")
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ribbon")
        img?.isTemplate = true
        item?.button?.image = img
        item?.button?.appearsDisabled = paused
        if isOpen { model.reload() }
    }

    @objc private func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { model.frontApp = front }
        model.reload()
        let hc = NSHostingController(rootView: PanelView(model: model) { [weak self] in self?.close() })
        hc.sizingOptions = [.preferredContentSize]
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 600), styleMask: [.borderless, .nonactivatingPanel],
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
        p.delegate = self
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
        p.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 4))
    }
}

final class PanelModel: ObservableObject {
    @Published var tick = 0
    var frontApp: NSRunningApplication?
    var key: ScreenKey?

    func reload() {
        key = WindowManager.shared.commandKey()
        tick += 1
    }
}

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
            if wm.isRunning, let key = model.key, let d = wm.display(uuid: key.display) {
                screenSection(key, d)
                switches(key, d)
            }
            frontAppRow
            Divider().padding(.horizontal, 4)
            VStack(spacing: 2) {
                row("gearshape", "Settings…", "⌘,") { close(); UIHub.shared.openSettings() }
                row("keyboard", "Keyboard Shortcuts", shortcutsHint) { close(); UIHub.shared.showCheatSheet() }
                row("power", "Quit Ribbon", "⌘Q") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(1)
    }

    // MARK: Header

    private var status: (Color, String) {
        if !AXPermission.isTrusted { return (.red, "Needs Accessibility access") }
        if !store.config.tilingEnabled { return (.gray, "Tiling is off") }
        if wm.pausedForStageManager { return (.orange, "Paused while Stage Manager is on") }
        if !wm.isRunning { return (.orange, "Starting…") }
        if let key = model.key, wm.cleanSpace.contains(key.display) { return (.green, "Clean Space") }
        if let key = model.key, wm.boards[key]?.zoomed != nil { return (.green, "Focus mode") }
        let n = wm.boards.filter { wm.isActive($0.key) }.reduce(0) { $0 + $1.value.windowCount }
        return (.green, n == 1 ? "Tiling 1 window" : "Tiling \(n) windows")
    }

    private var header: some View {
        let (color, text) = status
        return HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ribbon").font(.system(size: 14, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.6), radius: 2)
                    Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding<Bool>(get: { store.config.tilingEnabled }, set: { store.config.tilingEnabled = $0; model.reload() }))
                .toggleStyle(.switch).labelsHidden().tint(Brand.violet)
                .help("Arrange windows automatically")
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        if !AXPermission.isTrusted {
            card("hand.raised.fill", BadgeColors.red, "Ribbon needs Accessibility access to arrange your windows.", "Grant Access") {
                AXPermission.prompt()
                AXPermission.openSettings()
            }
        } else if IsSecureEventInputEnabled() {
            card("lock.fill", BadgeColors.orange, "Another app is using Secure Input, so shortcuts pause until it's done.", nil) {}
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

    // MARK: This screen

    private func screenSection(_ key: ScreenKey, _ d: Display) -> some View {
        let b = wm.boards[key] ?? Board()
        let arr = wm.arrangement(key, d)
        let cap = wm.capacity(key, d)
        let maxTiles = TileLayout.maxTiles(arr, area: wm.area(for: d))
        return VStack(alignment: .leading, spacing: 10) {
            ScreenMiniMap(key: key, display: d)
                .overlay(alignment: .bottomTrailing) {
                    if !b.splits.isDefault {
                        Button {
                            wm.resetSizes(key)
                            model.reload()
                        } label: {
                            Label("Reset sizes", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(QuietButtonStyle())
                        .padding(8)
                    }
                }
            HStack(spacing: 8) {
                Text("Windows on this screen").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            HStack(spacing: 8) {
                Picker("", selection: Binding<LayoutKind>(get: { wm.layoutKind(key) }, set: { wm.setLayout($0, for: key); model.reload() })) {
                    Text("Grid").tag(LayoutKind.grid)
                    Text("Columns").tag(LayoutKind.columns)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                .disabled(arr == .rows)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { (n: Int) in
                        Button { wm.setCapacity(n, for: key); model.reload() } label: {
                            Text("\(n)").font(.system(size: 12, weight: .bold)).frame(width: 30, height: 24)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(n == cap ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                                .foregroundStyle(n == cap ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(n > maxTiles)
                        .opacity(n > maxTiles ? 0.35 : 1)
                        .help(n == 1 ? "1 window on this screen" : "\(n) windows on this screen")
                    }
                }
            }
            if arr == .rows {
                Text("Tall screens always stack windows in rows.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func switches(_ key: ScreenKey, _ d: Display) -> some View {
        let c = store.config
        let clean = wm.cleanSpace.contains(d.uuid)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                tileButton("arrow.triangle.2.circlepath", "Tidy up", on: false) { wm.retile(); model.reload() }
                tileButton("square.dashed", "Borders", on: c.highlight != .none) {
                    store.config.highlight = c.highlight == .none ? .activeBorder : .none
                }
                tileButton("cursorarrow.motionlines", "Hover focus", on: c.hoverFocus) { store.config.hoverFocus.toggle() }
            }
            VStack(spacing: 6) {
                toggleRow("eye.slash", BadgeColors.indigo, "No peek", "Dim the other windows", isOn: wm.noPeek) {
                    wm.toggleNoPeek(); model.reload()
                }
                if wm.noPeek {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: Binding<Double>(get: { store.config.noPeekDim }, set: { store.config.noPeekDim = $0 }), in: 0.1...0.9)
                            .tint(Brand.violet)
                        Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 34)
                }
                toggleRow("rectangle.inset.filled", BadgeColors.violet, "Clean Space", "Just this window, for sharing", isOn: clean) {
                    wm.toggleCleanSpace(); model.reload()
                }
            }
        }
    }

    private func tileButton(_ symbol: String, _ title: String, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
            .foregroundStyle(on ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ symbol: String, _ colors: [Color], _ title: String, _ detail: String, isOn: Bool,
                           _ flip: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, colors: colors, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding<Bool>(get: { isOn }, set: { _ in flip() })).toggleStyle(.switch).labelsHidden()
                .controlSize(.small).tint(Brand.violet)
        }
    }

    @ViewBuilder
    private var frontAppRow: some View {
        if let app = model.frontApp, let bid = app.bundleIdentifier, wm.isRunning {
            let name = app.localizedName ?? bid
            HStack(spacing: 10) {
                Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tile \(name)").font(.system(size: 12.5, weight: .semibold))
                    Text("Off leaves its windows where you put them").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(get: { store.config.tiles(bid) }, set: { wm.setAppTiles($0, bundleID: bid, name: name) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Brand.violet)
            }
        }
    }

    private var shortcutsHint: String {
        if !store.config.shortcutsEnabled { return "Off" }
        if !HotkeyCenter.shared.failed.isEmpty { return "⚠︎" }
        return "⌃⌥/"
    }

    private func row(_ symbol: String, _ title: String, _ trailing: String, _ run: @escaping () -> Void) -> some View {
        PanelRow(symbol: symbol, title: title, trailing: trailing, run: run)
    }
}

private struct PanelRow: View {
    let symbol: String
    let title: String
    let trailing: String
    let run: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
                Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Color.primary.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A miniature of one screen: each tile with its app's icon; the window in use outlined.
struct ScreenMiniMap: View {
    let key: ScreenKey
    let display: Display

    var body: some View {
        let wm = WindowManager.shared
        let b = wm.boards[key] ?? Board()
        let frames = wm.tileFrames[key] ?? []
        let d = display.frame
        let aspect = CGFloat(d.w / max(1, d.h))
        return GeometryReader { geo in
            let k = geo.size.width / CGFloat(d.w)
            ZStack(alignment: .topLeading) {
                Wallpaper().opacity(0.9)
                if b.isEmpty {
                    Text("No windows here yet").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(Array(b.tiles.enumerated()), id: \.offset) { (pair: (offset: Int, element: Tile)) in
                    let i = pair.offset
                    let t = pair.element
                    if frames.indices.contains(i), b.zoomed == nil || b.zoomed == t.showing {
                        let f = b.zoomed == t.showing ? wm.area(for: display) : frames[i]
                        miniTile(t, active: t.showing == wm.focusedWindowID)
                            .frame(width: CGFloat(f.w) * k, height: CGFloat(f.h) * k)
                            .offset(x: CGFloat(f.x - d.x) * k, y: CGFloat(f.y - d.y) * k)
                    }
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func miniTile(_ t: Tile, active: Bool) -> some View {
        let w = WindowManager.shared.windows[t.showing]
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            if let pid = w?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if t.isStack {
                Text("\(t.windows.count)").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .padding(4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(active ? Brand.violet : Color.clear, lineWidth: 2))
        .padding(1)
    }
}
#endif
