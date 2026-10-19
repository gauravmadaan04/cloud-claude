// A tiny app that opens plain windows for Ribbon's end-to-end tests. It reports its own window
// frames to a JSON file (an independent check on where Ribbon put them) and takes simple
// commands from files dropped into a folder.
#if os(macOS)
import AppKit

final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let dir: URL
    var windows: [String: NSWindow] = [:]
    var order: [String] = []
    let palette: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemPurple, .systemTeal, .systemYellow, .systemRed]

    init(dir: URL) { self.dir = dir }

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        let count = args.firstIndex(of: "--windows").flatMap { Int(args[$0 + 1]) } ?? 3
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("cmd"), withIntermediateDirectories: true)
        if count > 0 { for i in 1...count { open("Fixture \(i)", resizable: true) } }
        if args.contains("--fixed") { open("Fixed", resizable: false, size: NSSize(width: 300, height: 260)) }
        if args.contains("--tabs") {
            let a = open("Tab A", resizable: true)
            let b = open("Tab B", resizable: true, show: false)
            a.addTabbedWindow(b, ordered: .above)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows[order.first ?? ""]?.makeKeyAndOrderFront(nil)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
    }

    @discardableResult
    func open(_ title: String, resizable: Bool, size: NSSize = NSSize(width: 640, height: 420), show: Bool = true) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let idx = order.count
        let rect = NSRect(x: 120 + idx * 40, y: 160 + idx * 30, width: Int(size.width), height: Int(size.height))
        let w = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.tabbingMode = title.hasPrefix("Tab") ? .preferred : .disallowed
        w.delegate = self
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = palette[idx % palette.count].withAlphaComponent(0.55).cgColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 44, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: v.centerXAnchor), label.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
        w.contentView = v
        if !resizable { w.styleMask.remove(.resizable); w.standardWindowButton(.zoomButton)?.isEnabled = false }
        windows[title] = w
        order.append(title)
        if show { w.makeKeyAndOrderFront(nil) }
        return w
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows[w.title] = nil
        order.removeAll { $0 == w.title }
    }

    func tick() {
        processCommands()
        let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]).frame.height
        let arr: [[String: Any]] = order.compactMap { t in
            guard let w = windows[t] else { return nil }
            let f = w.frame
            return ["title": t, "number": w.windowNumber, "frame": [f.origin.x, primaryH - f.origin.y - f.height, f.width, f.height],
                    "visible": w.isVisible, "key": w.isKeyWindow, "miniaturized": w.isMiniaturized]
        }
        let screens = NSScreen.screens.map { s -> [String: Any] in
            ["frame": [s.frame.origin.x, s.frame.origin.y, s.frame.width, s.frame.height],
             "visible": [s.visibleFrame.origin.x, primaryH - s.visibleFrame.origin.y - s.visibleFrame.height, s.visibleFrame.width, s.visibleFrame.height]]
        }
        let root: [String: Any] = ["windows": arr, "screens": screens, "active": NSApp.isActive]
        if let d = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? d.write(to: dir.appendingPathComponent("frames.json"), options: .atomic)
        }
    }

    func processCommands() {
        let cmdDir = dir.appendingPathComponent("cmd")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cmdDir.path).sorted() else { return }
        for f in files {
            try? FileManager.default.removeItem(at: cmdDir.appendingPathComponent(f))
            let parts = f.split(separator: "_").map(String.init)   // e.g. 0001_open_Fixture 9
            guard parts.count >= 3 else { continue }
            let action = parts[1], arg = parts[2...].joined(separator: "_")
            switch action {
            case "open": open(arg, resizable: true)
            case "close": windows[arg]?.close()
            case "focus": NSApp.activate(ignoringOtherApps: true); windows[arg]?.makeKeyAndOrderFront(nil)
            case "minimize": windows[arg]?.miniaturize(nil)
            case "unminimize": windows[arg]?.deminiaturize(nil)
            case "minwidth":
                // "minwidth_Fixture 1=900"
                let kv = arg.split(separator: "=")
                if kv.count == 2, let v = Double(kv[1]) { windows[String(kv[0])]?.minSize = NSSize(width: v, height: 200) }
            case "quit": NSApp.terminate(nil)
            default: break
            }
        }
    }
}

let dir = URL(fileURLWithPath: CommandLine.arguments.firstIndex(of: "--dir").map { CommandLine.arguments[$0 + 1] } ?? "/tmp/ribbon-fixture")
let app = NSApplication.shared
let fixture = Fixture(dir: dir)
app.delegate = fixture
app.setActivationPolicy(.regular)
app.run()
#else
print("macOS only")
#endif
