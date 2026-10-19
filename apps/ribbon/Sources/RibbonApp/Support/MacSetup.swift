#if os(macOS)
import AppKit
import RibbonCore

struct SetupCheck: Identifiable {
    enum Status {
        case ok, warn, info
        var symbol: String { self == .ok ? "✓" : (self == .warn ? "!" : "i") }
        var name: String { self == .ok ? "ok" : (self == .warn ? "warn" : "info") }
    }

    struct Fix {
        let title: String
        let action: () -> Void
    }

    let id: String
    let title: String
    let detail: String
    let status: Status
    var fixes: [Fix] = []
}

/// Checks macOS settings and other apps that get in the way of a scrolling window manager.
enum MacSetup {
    static let conflictingApps: [String: String] = [
        "com.knollsoft.Rectangle": "Rectangle", "com.knollsoft.Hookshot": "Rectangle Pro",
        "com.crowdcafe.windowmagnet": "Magnet", "com.manytricks.Moom": "Moom",
        "com.hegenberg.BetterSnapTool": "BetterSnapTool", "com.amethyst.Amethyst": "Amethyst",
        "io.ianyh.Amethyst": "Amethyst", "bobko.aerospace": "AeroSpace", "com.mizage.Divvy": "Divvy",
        "com.divisiblebyzero.Spectacle": "Spectacle", "com.MrKai77.Loop": "Loop",
        "co.highlyopinionated.swish": "Swish",
    ]
    /// Matched by app name when the bundle id isn't known.
    static let conflictingNames: Set<String> = ["ChainYourMac", "Mosaic", "Moom", "Magnet", "Rectangle", "Loop", "Swish", "Amethyst", "AeroSpace"]

    static func pref(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    static func boolPref(_ key: String, _ domain: String) -> Bool? { (pref(key, domain) as? NSNumber)?.boolValue }
    static func intPref(_ key: String, _ domain: String) -> Int? { (pref(key, domain) as? NSNumber)?.intValue }

    static func openSettings(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(u) }
    }

    static func shell(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
        p.waitUntilExit()
    }

    static func run() -> [SetupCheck] {
        var out: [SetupCheck] = []
        let cfg = SettingsStore.shared.config

        if AXPermission.isTrusted {
            out.append(SetupCheck(id: "ax", title: "Accessibility access", detail: "Ribbon can arrange your windows.", status: .ok))
        } else {
            out.append(SetupCheck(id: "ax", title: "Accessibility access",
                                  detail: "Needed to move and resize windows. Turn on Ribbon in Privacy & Security → Accessibility.",
                                  status: .warn, fixes: [.init(title: "Open Settings") { AXPermission.prompt(); AXPermission.openSettings() }]))
        }

        // Other window managers fight over the same windows.
        let running = NSWorkspace.shared.runningApplications
        let rivals = running.filter { app in
            (app.bundleIdentifier.map { conflictingApps[$0] != nil } ?? false) || conflictingNames.contains(app.localizedName ?? "")
        }
        var rivalNames = rivals.map { app in app.bundleIdentifier.flatMap { conflictingApps[$0] } ?? app.localizedName ?? "App" }
        let yabai = processRunning("yabai")
        if yabai { rivalNames.append("yabai") }
        if rivalNames.isEmpty {
            out.append(SetupCheck(id: "rivals", title: "Other window managers", detail: "None running.", status: .ok))
        } else {
            var fixes: [SetupCheck.Fix] = rivals.map { app in
                .init(title: "Quit \(app.localizedName ?? "app")") { app.terminate() }
            }
            if yabai { fixes.append(.init(title: "Stop yabai") { shell("/usr/bin/pkill -x yabai") }) }
            out.append(SetupCheck(id: "rivals", title: "Other window managers",
                                  detail: "\(Set(rivalNames).sorted().joined(separator: ", ")) also moves windows; the two will fight. Quit it, or turn off its snapping and shortcuts.",
                                  status: .warn, fixes: fixes))
        }

        if boolPref("GloballyEnabled", "com.apple.WindowManager") == true {
            out.append(SetupCheck(id: "stage", title: "Stage Manager", detail: "Stage Manager is on. It hides and shrinks windows, which breaks the strip.",
                                  status: .warn, fixes: [
                                      .init(title: "Turn off") { shell("defaults write com.apple.WindowManager GloballyEnabled -bool false") },
                                      .init(title: "Open Desktop & Dock") { openSettings("com.apple.Desktop-Settings.extension") },
                                  ]))
        } else {
            out.append(SetupCheck(id: "stage", title: "Stage Manager", detail: "Off.", status: .ok))
        }

        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
            let edge = boolPref("EnableTilingByEdgeDrag", "com.apple.WindowManager") ?? true
            let top = boolPref("EnableTopTilingByEdgeDrag", "com.apple.WindowManager") ?? true
            if edge || top {
                out.append(SetupCheck(id: "tiling", title: "macOS window tiling",
                                      detail: "Dragging a window to a screen edge makes macOS tile it, which can fight Ribbon's drag-to-reorder. Turn off \"Drag windows to screen edges to tile\".",
                                      status: .warn, fixes: [
                                          .init(title: "Turn off") {
                                              shell("defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false; defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false")
                                          },
                                          .init(title: "Open Desktop & Dock") { openSettings("com.apple.Desktop-Settings.extension") },
                                      ]))
            } else {
                out.append(SetupCheck(id: "tiling", title: "macOS window tiling", detail: "Edge tiling is off.", status: .ok))
            }
        }

        if NSScreen.screens.count > 1 {
            if boolPref("spans-displays", "com.apple.spaces") == true {
                out.append(SetupCheck(id: "spaces", title: "Displays have separate Spaces",
                                      detail: "This is off, so a window that scrolls past one display's edge can show on the next. Turn it on in Desktop & Dock (needs a log out).",
                                      status: .warn, fixes: [.init(title: "Open Desktop & Dock") { openSettings("com.apple.Desktop-Settings.extension") }]))
            } else {
                out.append(SetupCheck(id: "spaces", title: "Displays have separate Spaces", detail: "On. Each display keeps its own strip.", status: .ok))
            }
        }

        if boolPref("mru-spaces", "com.apple.dock") ?? true {
            out.append(SetupCheck(id: "mru", title: "Spaces stay in order",
                                  detail: "macOS reorders Spaces by recent use. Turning that off keeps each Space's strip where you expect it.",
                                  status: .info, fixes: [.init(title: "Keep Spaces in order") {
                                      shell("defaults write com.apple.dock mru-spaces -bool false; killall Dock")
                                  }]))
        } else {
            out.append(SetupCheck(id: "mru", title: "Spaces stay in order", detail: "On.", status: .ok))
        }

        if cfg.swipeEnabled {
            let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
            func any(_ key: String, _ test: (Int) -> Bool, default d: Int) -> Bool {
                domains.contains { test(intPref(key, $0) ?? d) }
            }
            var clashes: [String] = []
            if cfg.swipeFingers == 3 {
                if any("TrackpadThreeFingerHorizSwipeGesture", { $0 != 0 }, default: 0) {
                    clashes.append("three-finger swipes between pages or full-screen apps")
                }
                if any("TrackpadThreeFingerDrag", { $0 != 0 }, default: 0) { clashes.append("three-finger drag") }
            } else if any("TrackpadFourFingerHorizSwipeGesture", { $0 != 0 }, default: 2) {
                clashes.append("four-finger swipes between full-screen apps")
            }
            if clashes.isEmpty {
                out.append(SetupCheck(id: "swipe", title: "Trackpad swipe", detail: "\(cfg.swipeFingers)-finger swipes are free for Ribbon.", status: .ok))
            } else {
                out.append(SetupCheck(id: "swipe", title: "Trackpad swipe",
                                      detail: "macOS also uses \(clashes.joined(separator: " and ")). In Trackpad → More Gestures, set \"Swipe between full-screen applications\" to \(cfg.swipeFingers == 3 ? "four" : "three") fingers (or off), or switch Ribbon to \(cfg.swipeFingers == 3 ? "four" : "three") fingers.",
                                      status: .warn, fixes: [
                                          .init(title: "Open Trackpad settings") { openSettings("com.apple.Trackpad-Settings.extension") },
                                          .init(title: "Use \(cfg.swipeFingers == 3 ? 4 : 3) fingers instead") {
                                              SettingsStore.shared.config.swipeFingers = cfg.swipeFingers == 3 ? 4 : 3
                                          },
                                      ]))
            }
        }

        if LoginItem.isEnabled {
            out.append(SetupCheck(id: "login", title: "Open at login", detail: "Ribbon starts when you log in.", status: .ok))
        } else {
            out.append(SetupCheck(id: "login", title: "Open at login", detail: "Ribbon won't start by itself after a restart.",
                                  status: .info, fixes: [.init(title: "Open at login") { LoginItem.set(true) }]))
        }
        return out
    }

    static func processRunning(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func json(_ checks: [SetupCheck]) -> String {
        let arr = checks.map { ["id": $0.id, "title": $0.title, "detail": $0.detail, "status": $0.status.name] }
        guard let d = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }
}
#endif
