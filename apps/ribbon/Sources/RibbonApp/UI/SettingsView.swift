#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, layout, appearance, shortcuts, trackpad, apps, displays, setup, automation, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .trackpad: return "Trackpad & Mouse"
        case .apps: return "App Rules"
        case .displays: return "Displays"
        case .setup: return "Mac Setup"
        case .automation: return "Automation"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .appearance: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .trackpad: return "hand.draw"
        case .apps: return "square.stack.3d.up"
        case .displays: return "display.2"
        case .setup: return "checkmark.seal"
        case .automation: return "terminal"
        case .about: return "info.circle"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
}

struct SettingsView: View {
    @ObservedObject var nav: SettingsNavigation

    private var paneSelection: Binding<SettingsPane?> {
        Binding<SettingsPane?>(get: { nav.pane }, set: { (p: SettingsPane?) in if let p { nav.pane = p } })
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: paneSelection) { (pane: SettingsPane) in
                Label(pane.title, systemImage: pane.symbol).tag(Optional(pane))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch nav.pane {
                case .general: GeneralPane()
                case .layout: LayoutPane()
                case .appearance: AppearancePane()
                case .shortcuts: ShortcutsPane()
                case .trackpad: TrackpadPane()
                case .apps: AppsPane()
                case .displays: DisplaysPane()
                case .setup: MacSetupPane()
                case .automation: AutomationPane()
                case .about: AboutPane()
                }
            }
            .navigationTitle(nav.pane.title)
        }
    }
}

// MARK: - Helpers

/// Binding into one field of the live config; every change applies immediately.
func setting<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
    Binding<T>(get: { SettingsStore.shared.config[keyPath: kp] }, set: { (v: T) in SettingsStore.shared.config[keyPath: kp] = v })
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

private struct Hint: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var loginOn = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var trusted = AXPermission.isTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Ribbon is arranging windows", isOn: setting(\.tilingEnabled))
                Hint("Pausing puts every window back on screen and leaves them where they are. ⌃⌥Q toggles this anywhere.")
                LabeledContent("Accessibility access") {
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    } else {
                        Button("Grant Access…") { AXPermission.prompt(); AXPermission.openSettings() }
                    }
                }
            }
            Section("Startup") {
                Toggle("Open Ribbon when you log in", isOn: Binding<Bool>(get: { loginOn }, set: { (on: Bool) in
                    loginError = LoginItem.set(on)
                    loginOn = LoginItem.isEnabled
                }))
                if let loginError { Hint("Couldn't change this: \(loginError). Move Ribbon to Applications and try again.") }
                Toggle("Bring back my layout after a restart", isOn: setting(\.restoreSession))
                Hint("Column order, widths and stacks are saved for every display and Space.")
            }
            Section("Motion") {
                Toggle("Animate windows", isOn: setting(\.animate))
                LabeledContent("Speed") {
                    HStack {
                        Text("Fast").font(.caption).foregroundColor(.secondary)
                        Slider(value: setting(\.animationResponse), in: 0.12...0.5)
                        Text("Gentle").font(.caption).foregroundColor(.secondary)
                    }
                }
                .disabled(!store.config.animate)
            }
            Section("Help") {
                HStack {
                    Button("Show Welcome Tour") { UIHub.shared.showOnboarding() }
                    Button("Shortcut Cheat Sheet") { UIHub.shared.showCheatSheet() }
                    Spacer()
                    Button("Reset All Settings…") {
                        let a = NSAlert()
                        a.messageText = "Reset every Ribbon setting to its default?"
                        a.informativeText = "Your shortcuts, gaps, widths and app rules go back to how they were when you installed Ribbon."
                        a.addButton(withTitle: "Reset")
                        a.addButton(withTitle: "Cancel")
                        if a.runModal() == .alertFirstButtonReturn { store.resetToDefaults() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = AXPermission.isTrusted }
    }
}

// MARK: - Layout

struct LayoutPane: View {
    @ObservedObject private var store = SettingsStore.shared
    private let candidates: [Double] = [0.2, 0.25, 1.0 / 3, 0.4, 0.5, 0.6, 2.0 / 3, 0.75, 0.8, 0.9]

    var body: some View {
        Form {
            Section("Gaps") {
                LabeledContent("Between windows") {
                    HStack { Slider(value: setting(\.innerGap), in: 0...40, step: 1); Text("\(Int(store.config.innerGap)) pt").monospacedDigit().frame(width: 44) }
                }
                LabeledContent("At screen edges") {
                    HStack { Slider(value: setting(\.outerGap), in: 0...40, step: 1); Text("\(Int(store.config.outerGap)) pt").monospacedDigit().frame(width: 44) }
                }
                Hint("Set both to 0 for edge-to-edge windows. The Dock and menu bar are always left clear.")
            }
            Section("New windows") {
                Picker("Open new windows", selection: setting(\.newWindowPlacement)) {
                    ForEach(NewWindowPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Keep the width each window opens with", isOn: setting(\.useOwnWidth))
                Picker("Otherwise open them at", selection: setting(\.defaultWidth)) {
                    ForEach(store.config.widthPresets.sorted() + [1.0], id: \.self) { Text(percent($0)).tag($0) }
                }
                .disabled(store.config.useOwnWidth)
                Toggle("Keep each window's original height (top aligned)", isOn: setting(\.keepOriginalHeight))
                Toggle("Float fixed-size windows (Calculator, dialogs, settings)", isOn: setting(\.floatFixedSizeWindows))
            }
            Section("Scrolling") {
                Picker("Centre the focused window", selection: setting(\.centerMode)) {
                    ForEach(CenterMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("When windows don't fill the screen", selection: setting(\.sparse)) {
                    ForEach(SparseAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Hint("⌃⌥C centres the focused window once, whatever this is set to.")
            }
            Section("Preset widths (⌃⌥R cycles through them)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
                    ForEach(candidates, id: \.self) { v in
                        let on = store.config.widthPresets.contains { abs($0 - v) < 0.001 }
                        Button(percent(v)) {
                            var p = store.config.widthPresets.filter { abs($0 - v) > 0.001 }
                            if !on { p.append(v) }
                            if !p.isEmpty { store.config.widthPresets = p.sorted() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(on ? .accentColor : Color.gray.opacity(0.35))
                    }
                }
            }
            Section("Tabbed columns") {
                LabeledContent("Tab bar height") {
                    HStack { Slider(value: setting(\.tabBarHeight), in: 22...40, step: 1); Text("\(Int(store.config.tabBarHeight)) pt").monospacedDigit().frame(width: 44) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @ObservedObject private var store = SettingsStore.shared

    private var borderColor: Binding<Color> {
        Binding<Color>(get: { Color(nsColor: NSColor(hex: SettingsStore.shared.config.borderColor) ?? NSColor.systemBlue) },
                       set: { (c: Color) in SettingsStore.shared.config.borderColor = NSColor(c).hexString })
    }

    var body: some View {
        Form {
            Section("Focus border") {
                Toggle("Draw a border around the focused window", isOn: setting(\.focusBorder))
                ColorPicker("Colour", selection: borderColor, supportsOpacity: false)
                LabeledContent("Thickness") {
                    HStack { Slider(value: setting(\.borderWidth), in: 1...10, step: 1); Text("\(Int(store.config.borderWidth)) pt").monospacedDigit().frame(width: 44) }
                }
                LabeledContent("Corner radius") {
                    HStack { Slider(value: setting(\.borderRadius), in: 0...28, step: 1); Text("\(Int(store.config.borderRadius)) pt").monospacedDigit().frame(width: 44) }
                }
            }
            .disabled(false)
            Section("Dimming") {
                Toggle("Dim windows that aren't focused", isOn: setting(\.dimUnfocused))
                LabeledContent("Amount") {
                    HStack { Slider(value: setting(\.dimAmount), in: 0.05...0.6); Text(percent(store.config.dimAmount)).monospacedDigit().frame(width: 44) }
                }
                .disabled(!store.config.dimUnfocused)
            }
            Section("Strip map") {
                Toggle("Flash the strip map when the strip scrolls", isOn: setting(\.showIndicatorOnScroll))
                Toggle("Show it while I hold ⌃⌥", isOn: setting(\.showIndicatorOnHold))
                Picker("Position", selection: setting(\.indicatorPosition)) {
                    ForEach(IndicatorPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Hint("While it's showing you can click a tile to jump to that window, or drag tiles to reorder.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var filter = ""

    var body: some View {
        let conflicts = store.config.conflicts()
        Form {
            Section {
                HStack {
                    TextField("Search shortcuts", text: $filter).textFieldStyle(.roundedBorder)
                    Button("Restore Defaults") { store.config.bindings = [:] }
                }
                Hint("Click a shortcut to change it, then press the new keys. Delete removes it, Esc cancels. Keys are matched by position, so they work with any keyboard layout.")
                if !HotkeyCenter.shared.failed.isEmpty {
                    Label("Taken by another app: \(HotkeyCenter.shared.failed.map { KeyboardLayout.label($0) }.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
            ForEach(Command.Category.allCases, id: \.self) { cat in
                let cmds = Command.allCases.filter { $0.category == cat && matches($0) }
                if !cmds.isEmpty {
                    Section(cat.rawValue) {
                        ForEach(cmds, id: \.self) { cmd in
                            ShortcutRow(command: cmd, conflicts: conflicts)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func matches(_ c: Command) -> Bool {
        filter.isEmpty || c.title.localizedCaseInsensitiveContains(filter) || c.rawValue.contains(filter.lowercased())
    }
}

struct ShortcutRow: View {
    let command: Command
    let conflicts: [KeyCombo: [Command]]
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        let combos = store.config.combos(for: command)
        HStack {
            Text(command.title)
            Spacer()
            ForEach(Array(combos.enumerated()), id: \.offset) { i, combo in
                RecorderButton(combo: combo, clash: (conflicts[combo]?.count ?? 0) > 1) { new in
                    var list = combos
                    if let new { list[i] = new } else { list.remove(at: i) }
                    store.config.bindings[command.rawValue] = list
                }
            }
            RecorderButton(combo: nil, clash: false) { new in
                guard let new else { return }
                store.config.bindings[command.rawValue] = combos + [new]
            }
            if store.config.bindings[command.rawValue] != nil {
                Button { store.config.bindings[command.rawValue] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Back to the default")
            }
        }
    }
}

/// Click, then press keys. Hotkeys are paused while recording so the keys reach us.
struct RecorderButton: View {
    let combo: KeyCombo?
    let clash: Bool
    let onChange: (KeyCombo?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Group {
                if recording { Text("Type keys…").foregroundColor(.accentColor) }
                else if let combo { Text(KeyboardLayout.label(combo)).font(.system(.body, design: .rounded).weight(.medium)) }
                else { Image(systemName: "plus") }
            }
            .frame(minWidth: combo == nil && !recording ? 18 : 60)
        }
        .buttonStyle(.bordered)
        .tint(clash ? .orange : nil)
        .help(clash ? "This shortcut is used twice; only the first command gets it." : "Click to record a shortcut")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = HotkeyCenter.modifiers(from: e.modifierFlags)
            if e.keyCode == 53 && mods.isEmpty { stop(); return nil }
            if (e.keyCode == 51 || e.keyCode == 117) && mods.isEmpty {
                if combo != nil { onChange(nil) }
                stop()
                return nil
            }
            guard !mods.isEmpty || (0x60...0x7A).contains(Int(e.keyCode)) else { NSSound.beep(); return nil }
            onChange(KeyCombo(keyCode: UInt32(e.keyCode), modifiers: mods))
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording { HotkeyCenter.shared.resume() }
        recording = false
    }
}

// MARK: - Trackpad

struct TrackpadPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var checks: [SetupCheck] = []

    var body: some View {
        Form {
            Section("Trackpad swipe") {
                Toggle("Swipe to scroll the strip", isOn: setting(\.swipeEnabled))
                Picker("Fingers", selection: setting(\.swipeFingers)) {
                    Text("Three").tag(3)
                    Text("Four").tag(4)
                }
                .pickerStyle(.segmented)
                Toggle("Natural direction (windows follow your fingers)", isOn: setting(\.swipeNatural))
                LabeledContent("Sensitivity") {
                    HStack { Text("Low").font(.caption); Slider(value: setting(\.swipeSensitivity), in: 0.4...2.5); Text("High").font(.caption) }
                }
                if let c = checks.first(where: { $0.id == "swipe" }) {
                    SetupCheckRow(check: c) { checks = MacSetup.run() }
                }
                if !TrackpadWatcher.shared.isAvailable {
                    Hint("This Mac's trackpad driver isn't available, so swipes are off.")
                }
            }
            Section("Mouse") {
                Toggle("Hold ⌃⌥ and scroll to move the strip", isOn: setting(\.scrollWheelWithModifiers))
                Toggle("Focus follows the mouse", isOn: setting(\.focusFollowsMouse))
                Hint("Focus follows the mouse only for windows that are fully on screen, so the strip never jumps while you point.")
            }
        }
        .formStyle(.grouped)
        .onAppear { checks = MacSetup.run() }
        .onChange(of: store.config.swipeFingers) { _ in checks = MacSetup.run() }
    }
}

// MARK: - App rules

struct AppsPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Hint("Choose how each app's windows are handled. Float keeps them free to move on top; Ignore leaves the app alone completely.")
                Menu("Add an App…") {
                    ForEach(runningApps(), id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            guard let b = app.bundleIdentifier else { return }
                            store.config.appRules.append(AppRule(bundleID: b, name: app.localizedName ?? b, behavior: .float))
                        }
                    }
                }
            }
            Section("Rules") {
                ForEach(store.config.appRules) { rule in
                    HStack {
                        if let icon = icon(for: rule.bundleID) { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        VStack(alignment: .leading) {
                            Text(rule.name)
                            Text(rule.bundleID).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: ruleBinding(rule.bundleID, \.behavior)) {
                            ForEach(AppBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .frame(width: 170)
                        Picker("", selection: ruleBinding(rule.bundleID, \.width)) {
                            Text("Default width").tag(Double?.none)
                            ForEach([0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1.0], id: \.self) { Text(percent($0)).tag(Double?.some($0)) }
                        }
                        .frame(width: 130)
                        .disabled(rule.behavior != .tile)
                        Button { store.config.appRules.removeAll { $0.bundleID == rule.bundleID } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func ruleBinding<T>(_ bundle: String, _ kp: WritableKeyPath<AppRule, T>) -> Binding<T> {
        Binding<T>(get: {
            store.config.appRules.first { $0.bundleID == bundle }![keyPath: kp]
        }, set: { (v: T) in
            if let i = store.config.appRules.firstIndex(where: { $0.bundleID == bundle }) { store.config.appRules[i][keyPath: kp] = v }
        })
    }

    private func runningApps() -> [NSRunningApplication] {
        let have = Set(store.config.appRules.map { $0.bundleID.lowercased() })
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !have.contains($0.bundleIdentifier!.lowercased()) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func icon(for bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: - Displays

struct DisplaysPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Hint("Each display has its own strip, focus and scroll position. Turn a display off to leave its windows alone (handy for a presentation screen). ⌃⌥N sends a window to the next display.")
            }
            Section("Displays") {
                ForEach(Displays.current(), id: \.uuid) { d in
                    Toggle(isOn: Binding<Bool>(get: { !store.config.excludedDisplays.contains(d.uuid) }, set: { (on: Bool) in
                        store.config.excludedDisplays.removeAll { $0 == d.uuid }
                        if !on { store.config.excludedDisplays.append(d.uuid) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(d.name + (d.isMain ? " (main)" : ""))
                            Text("\(Int(d.frame.w)) × \(Int(d.frame.h)) pt").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Mac Setup

struct SetupCheckRow: View {
    let check: SetupCheck
    var onFix: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title).fontWeight(.medium)
                Text(check.detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if !check.fixes.isEmpty {
                    HStack {
                        ForEach(Array(check.fixes.enumerated()), id: \.offset) { _, fix in
                            Button(fix.title) {
                                fix.action()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onFix() }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    private var color: Color {
        switch check.status {
        case .ok: return .green
        case .warn: return .orange
        case .info: return .blue
        }
    }
}

struct MacSetupList: View {
    @State private var checks: [SetupCheck] = MacSetup.run()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ForEach(checks) { c in SetupCheckRow(check: c) { checks = MacSetup.run() } }
            .onReceive(timer) { _ in checks = MacSetup.run() }
    }
}

struct MacSetupPane: View {
    var body: some View {
        Form {
            Section {
                Hint("Ribbon checks the macOS settings and apps that can get in its way. Everything here is optional except Accessibility access.")
            }
            Section("Checks") { MacSetupList() }
            Section("If something looks wrong") {
                Hint("• Windows jump back after you move them: another window manager is running, or macOS edge tiling is on.\n• A swipe switches desktops instead of scrolling: macOS uses the same number of fingers (see Trackpad).\n• Ribbon stopped working after an update: open Privacy & Security → Accessibility, remove Ribbon with the – button, then add it again.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation

struct AutomationPane: View {
    @State private var cliStatus = AutomationPane.cliInstalledPath()
    @State private var message: String?

    var body: some View {
        Form {
            Section("URL scheme") {
                Hint("Every command has a link. Use them from Shortcuts, Alfred, Keyboard Maestro, Stream Deck or a script:")
                Text("open -g \"ribbon://focus-right\"\nopen -g \"ribbon://cycle-width\"\nopen -g \"ribbon://focus-window/<window number>\"")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
            Section("Command-line tool") {
                Hint("`ribbon focus-left`, `ribbon state` (JSON of every strip and window), `ribbon config set innerGap 6`, `ribbon doctor`. Run `ribbon help` for the full list.")
                HStack {
                    if let p = cliStatus { Label("Installed at \(p)", systemImage: "checkmark.circle.fill").foregroundColor(.green) }
                    Spacer()
                    Button(cliStatus == nil ? "Install `ribbon` Command…" : "Reinstall…") { installCLI() }
                }
            }
            Section("Raycast") {
                Hint("Exports one Raycast script command per Ribbon command. In Raycast: Settings → Extensions → + → Add Script Directory, then pick the folder.")
                Button("Export Raycast Commands…") { exportRaycast() }
            }
            Section("Diagnostics") {
                HStack {
                    Button("Copy Diagnostics") { copyDiagnostics() }
                    Button("Open Log Folder") {
                        NSWorkspace.shared.open(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Ribbon"))
                    }
                }
            }
            if let message { Section { Text(message).foregroundColor(.secondary) } }
        }
        .formStyle(.grouped)
    }

    static func cliInstalledPath() -> String? {
        for p in ["/usr/local/bin/ribbon", "/opt/homebrew/bin/ribbon"] where FileManager.default.fileExists(atPath: p) { return p }
        return nil
    }

    private func installCLI() {
        let src = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ribbon").path
        guard FileManager.default.fileExists(atPath: src) else { message = "The tool isn't inside this copy of Ribbon."; return }
        let script = "do shell script \"mkdir -p /usr/local/bin && ln -sf '\(src)' /usr/local/bin/ribbon\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        cliStatus = AutomationPane.cliInstalledPath()
        message = err == nil ? "Installed. Open a new Terminal window and try `ribbon help`." : "Not installed: \(err?["NSAppleScriptErrorMessage"] ?? "cancelled")"
    }

    private func exportRaycast() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the Raycast script commands"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let out = dir.appendingPathComponent("Ribbon Raycast Commands")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for s in RaycastScripts.scripts() {
            let u = out.appendingPathComponent(s.filename)
            try? s.contents.write(to: u, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        message = "Exported \(Command.allCases.count) commands to \(out.path)"
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }

    private func copyDiagnostics() {
        let text = """
        Ribbon \(AppInfo.version) (\(AppInfo.build)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        --- Mac Setup
        \(MacSetup.run().map { "\($0.status.symbol) \($0.title): \($0.detail)" }.joined(separator: "\n"))
        --- State
        \(WindowManager.shared.stateJSON())
        --- Log
        \(Log.recent())
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = "Copied. It lists app names and window titles, so check it before sharing."
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Ribbon").font(.largeTitle.bold())
            Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundColor(.secondary)
            Text("A scrolling window manager for macOS. Windows sit side by side on an endless strip, so opening one never squeezes the others.")
                .multilineTextAlignment(.center).frame(maxWidth: 440)
            Divider().frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 6) {
                Label("No account and no telemetry.", systemImage: "hand.raised")
                Label("Never reads what's on your screen; it only moves windows.", systemImage: "eye.slash")
                Label("Needs only Accessibility access. No kernel extensions, no SIP changes.", systemImage: "lock.shield")
            }
            .foregroundColor(.secondary)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}
#endif
