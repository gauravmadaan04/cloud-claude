#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// The menu bar item: a live header (status and a little map of the strip) above the commands.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.image = icon(paused: false)
        it.button?.toolTip = "Ribbon"
        menu.delegate = self
        menu.autoenablesItems = false
        it.menu = menu
        item = it
        refresh()
    }

    private func icon(paused: Bool) -> NSImage? {
        let img = NSImage(systemSymbolName: paused ? "pause.rectangle" : "rectangle.split.3x1", accessibilityDescription: "Ribbon")
        img?.isTemplate = true
        return img
    }

    func refresh() {
        let c = SettingsStore.shared.config
        let paused = !c.tilingEnabled || !WindowManager.shared.isRunning
        item?.button?.image = icon(paused: paused)
        item?.button?.appearsDisabled = paused
    }

    /// Opens the menu (used by the screenshot tests).
    func open() { DispatchQueue.main.async { self.item?.button?.performClick(nil) } }
    func close() { menu.cancelTracking() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config

        let header = NSMenuItem()
        let host = NSHostingView(rootView: MenuHeaderView())
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 128)
        header.view = host
        menu.addItem(header)
        menu.addItem(.separator())

        if !AXPermission.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", "hand.raised.fill", #selector(grantAccess)))
            menu.addItem(.separator())
        }
        menu.addItem(item(c.tilingEnabled ? "Pause Ribbon" : "Resume Ribbon", c.tilingEnabled ? "pause.circle" : "play.circle",
                          #selector(toggleTiling), command: .toggleTiling))
        menu.addItem(item("Re-arrange Windows", "arrow.triangle.2.circlepath", #selector(arrange)))
        menu.addItem(item("Show Strip Map", "rectangle.split.3x1", #selector(showStrip), command: .showStrip))
        menu.addItem(item("Keyboard Shortcuts", "keyboard", #selector(cheatSheet), command: .showShortcuts))

        if let key = wm.commandKey(), let s = wm.strips[key], !s.isEmpty {
            let sub = NSMenu()
            for (i, col) in s.columns.enumerated() {
                for wid in col.windows {
                    guard let w = wm.windows[wid] else { continue }
                    let title = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)"
                    let mi = NSMenuItem(title: String(title.prefix(60)), action: #selector(focusWindow(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.tag = Int(wid)
                    mi.state = wid == wm.focusedWindowID ? .on : .off
                    if i < 9, wid == col.activeWindow { mi.keyEquivalent = "\(i + 1)"; mi.keyEquivalentModifierMask = [.control, .option] }
                    mi.image = NSRunningApplication(processIdentifier: w.pid)?.icon.map { img in
                        let copy = img.copy() as! NSImage
                        copy.size = NSSize(width: 16, height: 16)
                        return copy
                    }
                    sub.addItem(mi)
                }
            }
            let windowsItem = item("Windows on This Strip", "macwindow.on.rectangle", nil)
            windowsItem.submenu = sub
            menu.addItem(windowsItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", "gearshape", #selector(settings), key: ","))
        menu.addItem(item("Mac Setup…", "checkmark.seal", #selector(macSetup)))
        menu.addItem(item("Welcome Tour…", "sparkles", #selector(tour)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Ribbon", "power", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ symbol: String?, _ sel: Selector?, key: String = "", command: Command? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if let command, let combo = SettingsStore.shared.config.combos(for: command).first {
            let name = KeyboardLayout.name(for: combo.keyCode)?.lowercased() ?? ""
            if name.count == 1 {
                mi.keyEquivalent = name
                var flags: NSEvent.ModifierFlags = []
                if combo.modifiers.contains(.control) { flags.insert(.control) }
                if combo.modifiers.contains(.option) { flags.insert(.option) }
                if combo.modifiers.contains(.shift) { flags.insert(.shift) }
                if combo.modifiers.contains(.command) { flags.insert(.command) }
                mi.keyEquivalentModifierMask = flags
            }
        }
        return mi
    }

    @objc private func grantAccess() { AXPermission.prompt(); AXPermission.openSettings() }
    @objc private func toggleTiling() { WindowManager.shared.perform(.toggleTiling) }
    @objc private func arrange() { WindowManager.shared.perform(.arrange) }
    @objc private func showStrip() { UIHub.shared.showIndicator(for: WindowManager.shared.commandKey(), duration: 3) }
    @objc private func cheatSheet() { UIHub.shared.showCheatSheet() }
    @objc private func settings() { UIHub.shared.openSettings() }
    @objc private func macSetup() { UIHub.shared.openSettings(tab: SettingsPane.setup.rawValue) }
    @objc private func tour() { UIHub.shared.showOnboarding(step: 0) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func focusWindow(_ sender: NSMenuItem) { WindowManager.shared.focus(window: WindowID(sender.tag)) }
}

/// The top of Ribbon's menu.
struct MenuHeaderView: View {
    var body: some View {
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config
        let running = wm.isRunning
        let key = wm.commandKey()
        let strip = key.flatMap { wm.strips[$0] }
        let count = strip?.windowCount ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ribbon").font(.system(size: 14, weight: .bold))
                    Text(statusText(running: running, tiling: c.tilingEnabled, count: count))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(running ? Color.green : Color.orange).frame(width: 8, height: 8)
                    .shadow(color: (running ? Color.green : Color.orange).opacity(0.6), radius: 3)
            }
            miniMap(strip)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: 300, height: 128, alignment: .topLeading)
    }

    private func statusText(running: Bool, tiling: Bool, count: Int) -> String {
        if !AXPermission.isTrusted { return "Needs Accessibility access" }
        if !tiling { return "Paused" }
        if !running { return "Starting…" }
        return count == 1 ? "1 window on this strip" : "\(count) windows on this strip"
    }

    @ViewBuilder
    private func miniMap(_ strip: Strip?) -> some View {
        let wm = WindowManager.shared
        if let s = strip, !s.isEmpty {
            let total = s.columns.reduce(0.0) { $0 + $1.width }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(s.columns.enumerated()), id: \.element.id) { i, col in
                        let w = col.activeWindow.flatMap { wm.windows[$0] }
                        let focused = s.focused == i
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(focused ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)))
                            if let icon = w.flatMap({ NSRunningApplication(processIdentifier: $0.pid)?.icon }) {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: max(14, (geo.size.width - CGFloat(s.columns.count - 1) * 3) * CGFloat(col.width / max(0.01, total))))
                    }
                }
            }
            .frame(height: 44)
        } else {
            HStack {
                Image(systemName: "rectangle.dashed").foregroundStyle(.secondary)
                Text("No windows on this display yet").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }
}
#endif
