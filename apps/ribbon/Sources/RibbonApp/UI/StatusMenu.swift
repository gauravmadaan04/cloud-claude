#if os(macOS)
import AppKit
import RibbonCore

/// The menu bar item.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.image = icon(paused: false)
        it.button?.toolTip = "Ribbon"
        menu.delegate = self
        it.menu = menu
        item = it
        refresh()
    }

    private func icon(paused: Bool) -> NSImage? {
        let name = paused ? "pause.rectangle" : "rectangle.split.3x1"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Ribbon")
        img?.isTemplate = true
        return img
    }

    func refresh() {
        let c = SettingsStore.shared.config
        let paused = !c.tilingEnabled || !WindowManager.shared.isRunning
        item?.button?.image = icon(paused: paused)
        item?.button?.appearsDisabled = paused
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let wm = WindowManager.shared
        let c = SettingsStore.shared.config

        let status: String
        if !AXPermission.isTrusted { status = "Needs Accessibility access" }
        else if !c.tilingEnabled { status = "Paused" }
        else if let key = wm.commandKey(), let s = wm.strips[key] {
            status = "\(s.windowCount) window\(s.windowCount == 1 ? "" : "s") on this strip"
        } else { status = "Tiling" }
        let header = NSMenuItem(title: "Ribbon — \(status)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !AXPermission.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(.separator())
        }
        let toggle = item(c.tilingEnabled ? "Pause Ribbon" : "Resume Ribbon", #selector(toggleTiling), command: .toggleTiling)
        menu.addItem(toggle)
        menu.addItem(item("Re-arrange Windows", #selector(arrange)))
        menu.addItem(item("Show Strip Map", #selector(showStrip), command: .showStrip))
        menu.addItem(item("Keyboard Shortcuts…", #selector(cheatSheet), command: .showShortcuts))

        if !wm.windows.isEmpty, let key = wm.commandKey(), let s = wm.strips[key], !s.isEmpty {
            let sub = NSMenu()
            for (i, col) in s.columns.enumerated() {
                for wid in col.windows {
                    guard let w = wm.windows[wid] else { continue }
                    let title = w.title.isEmpty ? w.appName : "\(w.appName) — \(w.title)"
                    let mi = NSMenuItem(title: "\(i + 1). \(title.prefix(60))", action: #selector(focusWindow(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.tag = Int(wid)
                    mi.state = wid == wm.focusedWindowID ? .on : .off
                    mi.image = NSRunningApplication(processIdentifier: w.pid)?.icon.map { img in
                        let i = img.copy() as! NSImage
                        i.size = NSSize(width: 16, height: 16)
                        return i
                    }
                    sub.addItem(mi)
                }
            }
            let windowsItem = NSMenuItem(title: "Windows on This Strip", action: nil, keyEquivalent: "")
            windowsItem.submenu = sub
            menu.addItem(windowsItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Mac Setup…", #selector(macSetup)))
        menu.addItem(item("Welcome Tour…", #selector(tour)))
        menu.addItem(.separator())
        let quit = item("Quit Ribbon", #selector(quit), key: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ sel: Selector, key: String = "", command: Command? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        if let command, let combo = SettingsStore.shared.config.combos(for: command).first {
            mi.keyEquivalent = KeyboardLayout.name(for: combo.keyCode)?.lowercased() ?? ""
            if mi.keyEquivalent.count != 1 { mi.keyEquivalent = "" }
            var flags: NSEvent.ModifierFlags = []
            if combo.modifiers.contains(.control) { flags.insert(.control) }
            if combo.modifiers.contains(.option) { flags.insert(.option) }
            if combo.modifiers.contains(.shift) { flags.insert(.shift) }
            if combo.modifiers.contains(.command) { flags.insert(.command) }
            mi.keyEquivalentModifierMask = flags
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
    @objc private func tour() { UIHub.shared.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func focusWindow(_ sender: NSMenuItem) { WindowManager.shared.focus(window: WindowID(sender.tag)) }
}
#endif
