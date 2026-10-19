#if os(macOS)
import AppKit
import RibbonCore

/// Answers the `ribbon` CLI (and ribbon:// URLs) over a local CFMessagePort.
final class IPCServer {
    static let shared = IPCServer()
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?

    func start() {
        guard port == nil else { return }
        var ctx = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        var shouldFree: DarwinBoolean = false
        guard let p = CFMessagePortCreateLocal(nil, IPC.portName as CFString, { _, _, data, _ in
            let req = data.flatMap { IPC.decode(IPC.Request.self, $0 as Data) }
            let resp = req.map { IPCServer.handle($0) } ?? IPC.Response(ok: false, message: "Bad request")
            return Unmanaged.passRetained(IPC.encode(resp) as CFData)
        }, &ctx, &shouldFree) else {
            Log.error("Another copy of Ribbon owns the command port")
            return
        }
        port = p
        source = CFMessagePortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// True if another Ribbon is already running (its port answers).
    static func otherInstanceRunning() -> Bool {
        CFMessagePortCreateRemote(nil, IPC.portName as CFString) != nil
    }

    static func handle(_ req: IPC.Request) -> IPC.Response {
        let wm = WindowManager.shared
        let store = SettingsStore.shared
        switch req.cmd {
        case "ping": return .init(ok: true, message: "pong")
        case "version": return .init(ok: true, message: "Ribbon \(AppInfo.version) (\(AppInfo.build))")
        case "state": return .init(ok: true, json: wm.stateJSON())
        case "doctor":
            let checks = MacSetup.run()
            let lines = checks.map { "\($0.status.symbol) \($0.title): \($0.detail)" }
            return .init(ok: true, message: lines.joined(separator: "\n"), json: MacSetup.json(checks))
        case "pause":
            wm.setTiling(false); return .init(ok: true, message: "Paused")
        case "resume":
            wm.setTiling(true); return .init(ok: true, message: wm.isRunning ? "Running" : "Waiting for Accessibility permission")
        case "quit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
            return .init(ok: true, message: "Quitting")
        case "focus-window":
            guard let s = req.args.first, let id = UInt32(s), wm.windows[id] != nil else {
                return .init(ok: false, message: "Unknown window")
            }
            wm.focus(window: id)
            return .init(ok: true)
        case "config":
            switch req.args.first {
            case "list":
                return .init(ok: true, json: String(decoding: store.config.encoded(), as: UTF8.self))
            case "get":
                guard req.args.count > 1, let v = store.config.value(of: req.args[1]) else { return .init(ok: false, message: "Unknown setting") }
                return .init(ok: true, message: v)
            case "set":
                guard req.args.count > 2 else { return .init(ok: false, message: "Usage: config set <key> <value>") }
                var c = store.config
                do {
                    try c.set(req.args[1], to: req.args[2...].joined(separator: " "))
                    store.config = c
                    return .init(ok: true, message: "\(req.args[1]) = \(c.value(of: req.args[1]) ?? "")")
                } catch {
                    return .init(ok: false, message: "\(error)")
                }
            case "reset":
                store.resetToDefaults(); return .init(ok: true, message: "Settings reset")
            default:
                return .init(ok: false, message: "Usage: config list | get <key> | set <key> <value> | reset")
            }
        case "show-onboarding":
            UIHub.shared.showOnboarding(step: req.args.first.flatMap { Int($0) }); return .init(ok: true)
        case "show-settings":
            UIHub.shared.openSettings(tab: req.args.first); return .init(ok: true)
        case "close-windows":
            UIHub.shared.closeAppWindows(); return .init(ok: true)
        default:
            guard let cmd = Command.parse(req.cmd) else {
                return .init(ok: false, message: "Unknown command '\(req.cmd)'. Try `ribbon help`.")
            }
            wm.perform(cmd)
            return .init(ok: true)
        }
    }
}
#endif
