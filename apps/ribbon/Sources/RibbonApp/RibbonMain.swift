#if os(macOS)
import AppKit
import RibbonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if IPCServer.otherInstanceRunning() && !args.contains("--force") {
            // A second launch (e.g. double-clicking the app again) just opens Settings in the first one.
            _ = CFMessagePortCreateRemote(nil, IPC.portName as CFString).map { port in
                CFMessagePortSendRequest(port, 0, IPC.encode(IPC.Request(cmd: "open-settings")) as CFData, 1, 1, nil, nil)
            }
            NSApp.terminate(nil)
            return
        }
        Log.trimFile()
        Log.info("Ribbon \(AppInfo.version) launched on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let store = SettingsStore.shared
        if args.contains("--reset") { store.config = Config() }
        if args.contains("--skip-onboarding") { store.config.hasCompletedOnboarding = true }
        if !AppInfo.isE2E { AXPermission.clearStaleEntryIfNeeded() }

        IPCServer.shared.start()
        UIHub.shared.setup()

        let hotkeys = HotkeyCenter.shared
        hotkeys.onCommand = { cmd in WindowManager.shared.perform(cmd) }
        hotkeys.apply(store.config)
        HoverFocus.shared.apply(store.config)
        TrackpadWatcher.shared.onSwipe = { ev in
            let wm = WindowManager.shared
            let c = SettingsStore.shared.config
            let width = wm.scrollingKeyUnderPointer().flatMap { wm.display(uuid: $0.display) }?.visible.w ?? 1440
            func pts(_ dx: Double) -> Double { SwipeMath.points(forPadDelta: dx, viewportWidth: width, sensitivity: c.swipeSensitivity, natural: c.swipeNatural) }
            switch ev {
            case .began(let dx):
                wm.interactiveBegin()
                wm.interactiveScroll(points: pts(dx))
            case .changed(let dx):
                wm.interactiveScroll(points: pts(dx))
            case .ended(let v):
                wm.interactiveEnd(velocityPoints: pts(v))
            }
        }
        applyScrollInput(store.config)
        store.onChange { [weak self] old, new in
            if old.bindings != new.bindings || old.shortcutsEnabled != new.shortcutsEnabled { HotkeyCenter.shared.apply(new) }
            if old.hoverFocus != new.hoverFocus || old.tilingEnabled != new.tilingEnabled { HoverFocus.shared.apply(new) }
            if old.swipeEnabled != new.swipeEnabled || old.swipeFingers != new.swipeFingers || old.tilingEnabled != new.tilingEnabled
                || old.scrollWheelWithModifiers != new.scrollWheelWithModifiers {
                self?.applyScrollInput(new)
            }
        }

        if !store.config.hasCompletedOnboarding {
            // Windows are tidied at the end of the tour.
            UIHub.shared.showOnboarding()
        } else {
            if !AXPermission.isTrusted { AXPermission.prompt() }
            WindowManager.shared.start()
        }
        if let i = args.firstIndex(of: "--show-settings") {
            UIHub.shared.openSettings(tab: args.indices.contains(i + 1) ? args[i + 1] : nil)
        }
    }

    /// Swipes and ⌃⌥ + scroll for screens that use the Scrolling layout.
    private func applyScrollInput(_ c: Config) {
        TrackpadWatcher.shared.stop()
        if c.swipeEnabled && c.tilingEnabled { TrackpadWatcher.shared.start(fingers: c.swipeFingers) }
        ScrollWheel.shared.apply(c)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UIHub.shared.openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let wm = WindowManager.shared
        if wm.isRunning { SessionStore.save(wm.snapshot()) }
        Log.info("Quit")
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s),
              let req = IPC.request(from: url) else { return }
        Log.info("URL \(s)")
        if req.cmd == "settings" { UIHub.shared.openSettings(tab: req.args.first); return }
        _ = IPCServer.handle(req)
    }
}

@main
enum RibbonMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
#else
@main
enum RibbonMain {
    static func main() { print("Ribbon runs on macOS only.") }
}
#endif
