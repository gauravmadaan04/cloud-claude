#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, layout, highlight, shortcuts, apps, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .highlight: return "Highlight"
        case .shortcuts: return "Shortcuts"
        case .apps: return "Apps"
        case .advanced: return "Advanced"
        case .about: return "About Ribbon"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "The main switch, startup and the little things."
        case .layout: return "Grid, columns or scrolling, how many windows per screen, and spacing."
        case .highlight: return "How the window you're using stands out, and No peek."
        case .shortcuts: return "Every shortcut, rebindable. Keys work on any keyboard layout."
        case .apps: return "Apps whose windows Ribbon leaves where you put them."
        case .advanced: return "Links, the command-line tool, Raycast and diagnostics."
        case .about: return "Version, privacy and credits."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "square.grid.2x2.fill"
        case .highlight: return "paintbrush.fill"
        case .shortcuts: return "keyboard.fill"
        case .apps: return "square.stack.3d.up.fill"
        case .advanced: return "terminal.fill"
        case .about: return "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: return BadgeColors.gray
        case .layout: return BadgeColors.indigo
        case .highlight: return BadgeColors.pink
        case .shortcuts: return BadgeColors.orange
        case .apps: return BadgeColors.violet
        case .advanced: return BadgeColors.gray
        case .about: return BadgeColors.brand
        }
    }

    var sidebarTitle: String { self == .about ? "About" : title }

    var keywords: String {
        switch self {
        case .general: return "pause login startup restore animation speed reset tour hover focus stage manager clean space background haptics"
        case .layout: return "grid columns scrolling strip swipe trackpad fingers width windows per screen spacing gap full stack float quick actions grip"
        case .highlight: return "border glow colour color no peek dim blur corner"
        case .shortcuts: return "keys hotkeys keyboard bindings"
        case .apps: return "exclude float ignore tile apps rules"
        case .advanced: return "url cli command line raycast diagnostics log"
        case .about: return "version privacy"
        }
    }

    static let groups: [[SettingsPane]] = [[.general, .layout, .highlight], [.shortcuts, .apps], [.advanced, .about]]
}

final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
}

/// Binding into one field of the live config; every change applies immediately.
func setting<T>(_ kp: WritableKeyPath<Config, T>) -> Binding<T> {
    Binding<T>(get: { SettingsStore.shared.config[keyPath: kp] }, set: { (v: T) in SettingsStore.shared.config[keyPath: kp] = v })
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var nav: SettingsNavigation
    @State private var search = ""

    private var paneSelection: Binding<SettingsPane?> {
        Binding<SettingsPane?>(get: { nav.pane }, set: { (p: SettingsPane?) in if let p { nav.pane = p } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: paneSelection) {
                ForEach(SettingsPane.groups.indices, id: \.self) { gi in
                    Section {
                        ForEach(SettingsPane.groups[gi].filter(matches)) { (pane: SettingsPane) in
                            HStack(spacing: 10) {
                                IconBadge(symbol: pane.symbol, colors: pane.colors, size: 22)
                                Text(pane.sidebarTitle).font(.system(size: 13)).lineLimit(1)
                            }
                            .padding(.vertical, 1)
                            .tag(Optional(pane))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 204, max: 250)
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PaneHeader(symbol: nav.pane.symbol, colors: nav.pane.colors, title: nav.pane.title, subtitle: nav.pane.subtitle)
                    paneContent
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(nav.pane)
            .navigationTitle(nav.pane.title)
        }
        .tint(Brand.violet)
        .frame(minWidth: 780, minHeight: 540)
    }

    private func matches(_ p: SettingsPane) -> Bool {
        search.isEmpty || p.title.localizedCaseInsensitiveContains(search) || p.keywords.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch nav.pane {
        case .general: GeneralPane()
        case .layout: LayoutPane()
        case .highlight: HighlightPane()
        case .shortcuts: ShortcutsPane()
        case .apps: AppsPane()
        case .advanced: AdvancedPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Building blocks

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 6)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            if let footer {
                Text(footer).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 6).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if divider { Divider().padding(.leading, 14) }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var divider = true
    let isOn: Binding<Bool>

    var body: some View {
        SettingRow(title: title, subtitle: subtitle, divider: divider) {
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

struct SliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double? = nil
    var divider = true
    let format: (Double) -> String

    var body: some View {
        SettingRow(title: title, divider: divider) {
            HStack(spacing: 10) {
                if let step {
                    Slider(value: value, in: range, step: step).frame(width: 220)
                } else {
                    Slider(value: value, in: range).frame(width: 220)
                }
                Text(format(value.wrappedValue)).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
            }
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var loginOn = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var trusted = AXPermission.isTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                    .shadow(color: Brand.violet.opacity(0.35), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.config.tilingEnabled ? "Ribbon is arranging your windows" : "Ribbon is off")
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 8) {
                        if trusted {
                            StatusPill(kind: .good, text: "Accessibility on")
                        } else {
                            StatusPill(kind: .warn, text: "Needs Accessibility")
                            Button("Grant Access…") { AXPermission.prompt(); AXPermission.openSettings() }
                                .buttonStyle(BrandButtonStyle())
                        }
                        if WindowManager.shared.pausedForStageManager {
                            StatusPill(kind: .info, text: "Paused for Stage Manager")
                        }
                    }
                }
                Spacer()
                Toggle("", isOn: setting(\.tilingEnabled)).toggleStyle(.switch).labelsHidden().controlSize(.large)
            }
            .card(padding: 18, radius: 16)

            SettingsGroup(title: "Startup") {
                SettingRow(title: "Open Ribbon when you log in", subtitle: loginError.map { "Couldn't change this: \($0). Move Ribbon to Applications first." }) {
                    Toggle("", isOn: Binding<Bool>(get: { loginOn }, set: { (on: Bool) in
                        loginError = LoginItem.set(on)
                        loginOn = LoginItem.isEnabled
                    })).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                ToggleRow(title: "Bring back my layout after a restart",
                          subtitle: "Window order, stacks, sizes and window counts are remembered for every screen.",
                          divider: false, isOn: setting(\.restoreSession))
            }

            SettingsGroup(title: "Behaviour") {
                ToggleRow(title: "Activate windows on hover", subtitle: "Rest the pointer on a window to switch to it.", isOn: setting(\.hoverFocus))
                ToggleRow(title: "Pause while Stage Manager is on", subtitle: "Stage Manager arranges windows itself; Ribbon steps aside.",
                          isOn: setting(\.pauseForStageManager))
                ToggleRow(title: "Trackpad taps", subtitle: "A gentle tap when windows fall into place.", divider: false, isOn: setting(\.haptics))
            }

            SettingsGroup(title: "Motion") {
                ToggleRow(title: "Animate windows", isOn: setting(\.animate))
                SettingRow(title: "Speed", divider: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        Slider(value: setting(\.animationResponse), in: 0.12...0.5).frame(width: 200)
                        Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    }
                    .disabled(!store.config.animate)
                }
            }

            SettingsGroup(title: "Clean Space", footer: "Clean Space (⌃⌥P) shows just the window you're using on a plain background: handy for screen sharing.") {
                SettingRow(title: "Background", divider: false) {
                    HStack(spacing: 8) {
                        ForEach(Backdrop.allCases, id: \.self) { (b: Backdrop) in
                            Button { store.config.backdrop = b } label: {
                                VStack(spacing: 4) {
                                    BackdropView(style: b).frame(width: 54, height: 34)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(store.config.backdrop == b ? Brand.violet : Color.primary.opacity(0.15),
                                                          lineWidth: store.config.backdrop == b ? 2.5 : 1))
                                    Text(b.title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            SettingsGroup(title: "Help") {
                SettingRow(title: "Welcome tour", subtitle: "Two minutes: permission, the basics and a few power tools.") {
                    Button("Open Tour") { UIHub.shared.showOnboarding(step: 0) }.buttonStyle(QuietButtonStyle())
                }
                SettingRow(title: "All shortcuts") {
                    HStack(spacing: 8) {
                        CommandKeys(command: .showShortcuts, size: .small)
                        Button("Show") { UIHub.shared.showCheatSheet() }.buttonStyle(QuietButtonStyle())
                    }
                }
                SettingRow(title: "Reset all settings", subtitle: "Shortcuts, layout, highlight and app choices go back to their defaults.", divider: false) {
                    Button("Reset…") { confirmReset() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .onReceive(timer) { _ in trusted = AXPermission.isTrusted }
    }

    private func confirmReset() {
        let a = NSAlert()
        a.messageText = "Reset every Ribbon setting?"
        a.informativeText = "Your shortcuts, layout, highlight and app choices go back to how they were when you installed Ribbon."
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.resetToDefaults() }
    }
}

// MARK: - Layout

/// The preview on the Layout and Highlight panes: the user's own settings on demo windows.
struct LivePreview: View {
    @ObservedObject private var store = SettingsStore.shared
    var highlight = false
    @State private var step = 0
    private let timer = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let c = store.config
        let n = c.layout == .scrolling ? 5 : min(c.windowsPerScreen, 4)
        var b = demoBoard(n, capacity: n)
        b.setActive(WindowID(step % n + 1))
        var style = PreviewStyle(config: c)
        style.dim = highlight && WindowManager.shared.noPeek ? c.noPeekDim : 0
        if !highlight { style.highlight = .activeBorder }
        return VStack(spacing: 10) {
            BoardPreview(board: b, style: style)
                .frame(maxWidth: 540)
            Label("Live preview. Changes apply to your windows straight away.", systemImage: "eye")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in withAnimation(Brand.spring) { step += 1 } }
    }
}

struct LayoutPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LivePreview()

            SettingsGroup(title: "Every screen", footer: "Each screen can pick its own from the menu bar panel: click the Ribbon icon, then a layout.") {
                SettingRow(title: "Layout") {
                    HStack(spacing: 6) {
                        ForEach(LayoutKind.allCases, id: \.self) { (k: LayoutKind) in
                            let on = store.config.layout == k
                            Button { store.config.layout = k } label: {
                                VStack(spacing: 4) {
                                    LayoutGlyph(kind: k, count: 3, on: on).frame(width: 40, height: 26)
                                        .padding(5)
                                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
                                    Text(k.title).font(.system(size: 11, weight: on ? .semibold : .regular))
                                }
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(k.title) layout")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                SettingRow(title: "Windows per screen", subtitle: "Grid and columns. A laptop fits up to three columns; a big monitor four.", divider: false) {
                    Picker("", selection: setting(\.windowsPerScreen)) {
                        ForEach(1...4, id: \.self) { (n: Int) in Text("\(n)").tag(n) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    .disabled(store.config.layout == .scrolling)
                }
            }

            SettingsGroup(title: "Scrolling layout", footer: "Windows sit side by side on a strip that runs past the screen edges, so a new window never squeezes the others. If macOS uses three-finger swipes to change desktops, pick four fingers here.") {
                SettingRow(title: "New column width") {
                    Picker("", selection: setting(\.scrollingWidth)) {
                        Text("⅓").tag(1.0 / 3)
                        Text("½").tag(0.5)
                        Text("⅔").tag(2.0 / 3)
                        Text("Full").tag(1.0)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
                ToggleRow(title: "Swipe to scroll", isOn: setting(\.swipeEnabled))
                SettingRow(title: "Fingers") {
                    Picker("", selection: setting(\.swipeFingers)) { Text("Three").tag(3); Text("Four").tag(4) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                        .disabled(!store.config.swipeEnabled)
                }
                ToggleRow(title: "Natural direction", subtitle: "Windows follow your fingers, like scrolling a page.", isOn: setting(\.swipeNatural))
                SettingRow(title: "Scroll with the mouse wheel while holding", divider: false) {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) { KeyCap(label: "⌃", size: .small); KeyCap(label: "⌥", size: .small) }
                        Toggle("", isOn: setting(\.scrollWheelWithModifiers)).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
            }

            SettingsGroup(title: "Spacing", footer: "Space between windows and around the edges. The menu bar and Dock always stay clear.") {
                SliderRow(title: "Spacing", value: setting(\.spacing), range: 0...24, step: 1, divider: false) { "\(Int($0)) pt" }
            }

            SettingsGroup(title: "When a screen is full") {
                SettingRow(title: "A new window") {
                    Picker("", selection: setting(\.whenFull)) {
                        ForEach(WhenFull.allCases, id: \.self) { (w: WhenFull) in Text(w.title).tag(w) }
                    }
                    .labelsHidden().frame(width: 260)
                }
                SettingRow(title: "Moving a window there with ⌃⌥ + arrow", divider: false) {
                    Picker("", selection: setting(\.intoFull)) {
                        ForEach(IntoFull.allCases, id: \.self) { (w: IntoFull) in Text(w.title).tag(w) }
                    }
                    .labelsHidden().frame(width: 220)
                }
            }

            SettingsGroup(title: "Quick actions", footer: "Rest the pointer on the grip for the window's stack and quick actions.") {
                ToggleRow(title: "Show the grip above windows", divider: false, isOn: setting(\.quickActions))
            }
        }
    }
}

// MARK: - Highlight

struct HighlightPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var noPeek = WindowManager.shared.noPeek
    private let swatches = ["#7C5CFF", "#4F8CFF", "#2BB673", "#FF9F0A", "#FF375F", "#BF5AF2", "#8E8E93"]

    var body: some View {
        let c = store.config
        VStack(alignment: .leading, spacing: 20) {
            LivePreview(highlight: true)

            SettingsGroup(title: "Window in use") {
                SettingRow(title: "Style") {
                    Picker("", selection: setting(\.highlight)) {
                        ForEach(Highlight.allCases, id: \.self) { (h: Highlight) in Text(h.title).tag(h) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300)
                }
                SettingRow(title: "Colour") {
                    HStack(spacing: 7) {
                        ForEach(swatches, id: \.self) { (hex: String) in
                            let on = c.highlightColor.uppercased() == hex
                            Circle().fill(Color(nsColor: NSColor(hex: hex) ?? .systemPurple)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0.8 : 0), lineWidth: 2).padding(-3))
                                .onTapGesture { store.config.highlightColor = hex }
                        }
                        ColorPicker("", selection: Binding<Color>(
                            get: { Color(nsColor: NSColor(hex: store.config.highlightColor) ?? .systemPurple) },
                            set: { (col: Color) in store.config.highlightColor = NSColor(col).hexString }), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                SliderRow(title: "Border width", value: setting(\.borderWidth), range: 1...8, step: 1) { "\(Int($0)) pt" }
                SliderRow(title: "Corner radius", value: setting(\.cornerRadius), range: 0...28, step: 1, divider: false) { "\(Int($0)) pt" }
            }

            SettingsGroup(title: "No peek", footer: "No peek (⌃⌥D) dims every window but the one you're using, so you can focus and nobody can read over your shoulder.") {
                SettingRow(title: "No peek is \(noPeek ? "on" : "off")") {
                    Button(noPeek ? "Turn Off" : "Try It") {
                        WindowManager.shared.toggleNoPeek()
                        noPeek = WindowManager.shared.noPeek
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                SliderRow(title: "Dim amount", value: setting(\.noPeekDim), range: 0.1...0.9) { percent($0) }
                ToggleRow(title: "Blur the other windows", subtitle: "Keeps them unreadable even when lightly dimmed.", divider: false,
                          isOn: setting(\.noPeekBlur))
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var filter = ""

    var body: some View {
        let conflicts = store.config.conflicts()
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup {
                ToggleRow(title: "Keyboard shortcuts", subtitle: "Turn off to use Ribbon only with the mouse and the menu bar.", divider: false,
                          isOn: setting(\.shortcutsEnabled))
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a command", text: $filter).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                Button("Restore Defaults") { store.config.bindings = [:] }.buttonStyle(QuietButtonStyle())
            }
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(Brand.violet)
                Text("Click a shortcut, then press the new keys. Delete removes it; Esc cancels.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !HotkeyCenter.shared.failed.isEmpty {
                Label("Taken by another app: \(HotkeyCenter.shared.failed.map { KeyboardLayout.label($0) }.joined(separator: ", ")). Pick other keys for them below.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.orange)
            }
            ForEach(Command.Category.allCases, id: \.self) { cat in
                let cmds = Command.allCases.filter { $0.category == cat && matches($0) }
                if !cmds.isEmpty {
                    SettingsGroup(title: cat.rawValue) {
                        ForEach(cmds, id: \.self) { (cmd: Command) in
                            ShortcutRow(command: cmd, conflicts: conflicts, divider: cmd != cmds.last)
                        }
                    }
                }
            }
            .disabled(!store.config.shortcutsEnabled)
            .opacity(store.config.shortcutsEnabled ? 1 : 0.5)
        }
    }

    private func matches(_ c: Command) -> Bool {
        filter.isEmpty || c.title.localizedCaseInsensitiveContains(filter) || c.rawValue.contains(filter.lowercased())
    }
}

struct ShortcutRow: View {
    let command: Command
    let conflicts: [KeyCombo: [Command]]
    var divider = true
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        let combos = store.config.combos(for: command)
        SettingRow(title: command.title, divider: divider) {
            HStack(spacing: 6) {
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
                    Button { store.config.bindings[command.rawValue] = nil } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Back to the default")
                }
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
    @State private var hover = false

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(clash ? "This shortcut is used twice; only the first command gets it." : "Click to record a shortcut")
        .onDisappear { stop() }
    }

    @ViewBuilder
    private var label: some View {
        if recording {
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Type keys").font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Brand.violet.opacity(0.15)))
            .overlay(Capsule().strokeBorder(Brand.violet.opacity(0.6)))
        } else if let combo {
            ShortcutKeys(combo: combo, size: .small)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(clash ? Color.orange : Color.primary.opacity(hover ? 0.25 : 0), lineWidth: 1.5))
        } else {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0.05)))
        }
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

// MARK: - Apps

struct AppsPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Dialogs, sheets and panels are never tiled. Add apps here to leave their windows where you put them. You can also switch the app in front on or off from the menu bar.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Menu {
                    ForEach(runningApps(), id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            guard let b = app.bundleIdentifier else { return }
                            store.config.appRules.append(AppRule(bundleID: b, name: app.localizedName ?? b, behavior: .float))
                        }
                    }
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .fixedSize()
            }
            SettingsGroup(title: "Not tiled") {
                if store.config.appRules.isEmpty {
                    SettingRow(title: "Every app is tiled", divider: false) { EmptyView() }
                }
                ForEach(store.config.appRules) { (rule: AppRule) in
                    ruleRow(rule)
                }
            }
        }
    }

    private func ruleRow(_ rule: AppRule) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                appIcon(rule.bundleID)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name).font(.system(size: 13, weight: .medium))
                    Text(rule.bundleID).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: ruleBinding(rule.bundleID, \.behavior)) {
                    Text("Don't tile").tag(AppBehavior.float)
                    Text("Ignore completely").tag(AppBehavior.ignore)
                    Text("Tile").tag(AppBehavior.tile)
                }
                .labelsHidden().frame(width: 170)
                Button { store.config.appRules.removeAll { $0.bundleID == rule.bundleID } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove: the app's windows tile again")
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            if rule.bundleID != store.config.appRules.last?.bundleID { Divider().padding(.leading, 54) }
        }
    }

    @ViewBuilder
    private func appIcon(_ bundle: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            IconBadge(symbol: "app.dashed", colors: BadgeColors.gray, size: 28)
        }
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
}

// MARK: - Advanced

struct AdvancedPane: View {
    @State private var cliStatus = AdvancedPane.cliInstalledPath()
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "URL scheme", footer: "Use these from Shortcuts, Alfred, Keyboard Maestro, a Stream Deck or any script.") {
                codeRow("open -g \"ribbon://swap-right\"")
                codeRow("open -g \"ribbon://tile-2\"")
                codeRow("open -g \"ribbon://focus-window/<number>\"", divider: false)
            }
            SettingsGroup(title: "Command-line tool", footer: "Try ribbon help, ribbon state (JSON of every screen and window) or ribbon config set spacing 12.") {
                SettingRow(title: cliStatus.map { "Installed at \($0)" } ?? "Not installed", divider: false) {
                    Button(cliStatus == nil ? "Install…" : "Reinstall…") { installCLI() }.buttonStyle(BrandButtonStyle())
                }
            }
            SettingsGroup(title: "Raycast", footer: "In Raycast: Settings → Extensions → + → Add Script Directory, then pick the exported folder.") {
                SettingRow(title: "One Raycast command per Ribbon command", divider: false) {
                    Button("Export…") { exportRaycast() }.buttonStyle(QuietButtonStyle())
                }
            }
            SettingsGroup(title: "Diagnostics") {
                SettingRow(title: "Copy diagnostics", subtitle: "The current layout and recent log lines. Includes app names and window titles.") {
                    Button("Copy") { copyDiagnostics() }.buttonStyle(QuietButtonStyle())
                }
                SettingRow(title: "Log folder", divider: false) {
                    Button("Open") {
                        NSWorkspace.shared.open(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Ribbon"))
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            if let message {
                Label(message, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func codeRow(_ code: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    message = "Copied \(code)"
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Copy")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if divider { Divider().padding(.leading, 14) }
        }
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
        cliStatus = AdvancedPane.cliInstalledPath()
        message = err == nil ? "Installed. Open a new Terminal window and try ribbon help." : "Not installed: \(err?["NSAppleScriptErrorMessage"] ?? "cancelled")"
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
        --- State
        \(WindowManager.shared.stateJSON())
        --- Log
        \(Log.recent())
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = "Diagnostics copied. Check them before sharing."
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Brand.gradient).frame(width: 150, height: 150).blur(radius: 40).opacity(0.55)
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            }
            Text("Ribbon").font(.system(size: 30, weight: .bold))
            Text("Version \(AppInfo.version) (\(AppInfo.build))").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("Windows that arrange themselves. Open a window and it takes its place; close one and the others fill the space.")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            SettingsGroup {
                SettingRow(title: "No account, no analytics, no network") { Image(systemName: "hand.raised.fill").foregroundStyle(Brand.violet) }
                SettingRow(title: "Never reads what's in your windows") { Image(systemName: "eye.slash.fill").foregroundStyle(Brand.violet) }
                SettingRow(title: "Only needs Accessibility; no kernel extensions", divider: false) { Image(systemName: "lock.shield.fill").foregroundStyle(Brand.violet) }
            }
            .frame(maxWidth: 440)
            Text("Native SwiftUI and AppKit · Apple silicon and Intel · macOS 13 or later")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
#endif
