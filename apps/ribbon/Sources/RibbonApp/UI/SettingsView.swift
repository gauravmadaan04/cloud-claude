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
        case .about: return "About Ribbon"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "The main switch, startup and motion."
        case .layout: return "Gaps, widths and how the strip scrolls."
        case .appearance: return "Focus border, dimming and the strip map."
        case .shortcuts: return "Every command, rebindable. Keys work on any keyboard layout."
        case .trackpad: return "Swipe through the strip, or scroll it with a mouse."
        case .apps: return "Choose how particular apps are handled."
        case .displays: return "Each display has its own strip."
        case .setup: return "macOS settings and apps that can get in the way."
        case .automation: return "URL scheme, command-line tool, Raycast and diagnostics."
        case .about: return "Version, privacy and credits."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "rectangle.split.3x1.fill"
        case .appearance: return "paintbrush.fill"
        case .shortcuts: return "keyboard.fill"
        case .trackpad: return "hand.draw.fill"
        case .apps: return "square.stack.3d.up.fill"
        case .displays: return "display.2"
        case .setup: return "checkmark.seal.fill"
        case .automation: return "terminal.fill"
        case .about: return "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: return BadgeColors.gray
        case .layout: return BadgeColors.indigo
        case .appearance: return BadgeColors.pink
        case .shortcuts: return BadgeColors.orange
        case .trackpad: return BadgeColors.teal
        case .apps: return BadgeColors.violet
        case .displays: return BadgeColors.blue
        case .setup: return BadgeColors.green
        case .automation: return BadgeColors.gray
        case .about: return BadgeColors.brand
        }
    }

    /// Shorter names for the sidebar.
    var sidebarTitle: String {
        switch self {
        case .trackpad: return "Trackpad"
        case .about: return "About"
        default: return title
        }
    }

    var keywords: String {
        switch self {
        case .general: return "pause login startup restore animation speed reset tour"
        case .layout: return "gaps width centre center scroll new windows preset tabs height"
        case .appearance: return "border colour color dim strip map indicator"
        case .shortcuts: return "keys hotkeys keyboard bindings"
        case .trackpad: return "swipe fingers mouse scroll focus follows"
        case .apps: return "rules float ignore tile apps"
        case .displays: return "monitor screen exclude"
        case .setup: return "check stage manager rectangle magnet conflicts gestures spaces"
        case .automation: return "url cli command line raycast diagnostics log"
        case .about: return "version privacy"
        }
    }

    static let groups: [[SettingsPane]] = [[.general, .layout, .appearance], [.shortcuts, .trackpad, .apps, .displays], [.setup, .automation, .about]]
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
            VStack(spacing: 0) {
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
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 214, max: 260)
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PaneHeader(symbol: nav.pane.symbol, colors: nav.pane.colors, title: nav.pane.title, subtitle: nav.pane.subtitle)
                    paneContent
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(nav.pane)
            .navigationTitle(nav.pane.title)
        }
        .tint(Brand.violet)
        .frame(minWidth: 820, minHeight: 560)
    }

    private func matches(_ p: SettingsPane) -> Bool {
        search.isEmpty || p.title.localizedCaseInsensitiveContains(search) || p.keywords.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder
    private var paneContent: some View {
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

/// A capsule that toggles; used for preset widths.
private struct ChipToggle: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(Brand.snappy, value: on)
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
                    Text(store.config.tilingEnabled ? "Ribbon is arranging your windows" : "Ribbon is paused")
                        .font(.system(size: 16, weight: .bold))
                    HStack(spacing: 8) {
                        if trusted {
                            StatusPill(kind: .good, text: "Accessibility on")
                        } else {
                            StatusPill(kind: .warn, text: "Needs Accessibility")
                            Button("Grant Access…") { AXPermission.prompt(); AXPermission.openSettings() }
                                .buttonStyle(BrandButtonStyle())
                        }
                        HStack(spacing: 4) {
                            Text("Pause anywhere with").font(.system(size: 11)).foregroundStyle(.secondary)
                            CommandKeys(command: .toggleTiling, size: .small)
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
                          subtitle: "Column order, widths and stacks are saved for every display and Space.",
                          divider: false, isOn: setting(\.restoreSession))
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

            SettingsGroup(title: "Help") {
                SettingRow(title: "Welcome tour", subtitle: "Permission, Mac check and the five essential shortcuts.") {
                    Button("Show Tour") { UIHub.shared.showOnboarding(step: 0) }.buttonStyle(QuietButtonStyle())
                }
                SettingRow(title: "Shortcut cheat sheet") {
                    HStack(spacing: 8) {
                        CommandKeys(command: .showShortcuts, size: .small)
                        Button("Show") { UIHub.shared.showCheatSheet() }.buttonStyle(QuietButtonStyle())
                    }
                }
                SettingRow(title: "Reset all settings", subtitle: "Shortcuts, gaps, widths and app rules go back to their defaults.", divider: false) {
                    Button("Reset…") { confirmReset() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .onReceive(timer) { _ in trusted = AXPermission.isTrusted }
    }

    private func confirmReset() {
        let a = NSAlert()
        a.messageText = "Reset every Ribbon setting?"
        a.informativeText = "Your shortcuts, gaps, widths and app rules go back to how they were when you installed Ribbon."
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.resetToDefaults() }
    }
}

// MARK: - Layout

/// The preview on the Layout and Appearance panes: the user's own settings on a demo strip.
struct LivePreview: View {
    @ObservedObject private var store = SettingsStore.shared
    var appearance = false
    @State private var strip = demoStrip(count: 5, focus: 1)
    @State private var tick = 0
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let c = store.config
        let params = previewParams(c)
        var s = strip
        s.scroll = Layout.scrollToReveal(s, params)
        let border: (color: Color, width: Double, radius: Double)? = appearance && c.focusBorder
            ? (Color(nsColor: NSColor(hex: c.borderColor) ?? .systemBlue), c.borderWidth, c.borderRadius) : nil
        return VStack(spacing: 10) {
            StripPreview(strip: s, params: params, border: border, dim: appearance && c.dimUnfocused ? c.dimAmount : 0, showDock: true)
                .frame(maxWidth: 560)
            Label("Live preview. Changes apply to your windows straight away.", systemImage: "eye")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in
            tick += 1
            var n = strip
            if tick % 6 < 3 { n.focusRight() } else { n.focusLeft() }
            strip = n
        }
    }
}

struct LayoutPane: View {
    @ObservedObject private var store = SettingsStore.shared
    private let candidates: [Double] = [0.25, 1.0 / 3, 0.4, 0.5, 0.6, 2.0 / 3, 0.75, 0.9]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LivePreview()

            SettingsGroup(title: "Gaps", footer: "Set both to 0 for edge-to-edge windows. The menu bar and Dock always stay clear.") {
                SliderRow(title: "Between windows", value: setting(\.innerGap), range: 0...40, step: 1) { "\(Int($0)) pt" }
                SliderRow(title: "At the screen edges", value: setting(\.outerGap), range: 0...40, step: 1, divider: false) { "\(Int($0)) pt" }
            }

            SettingsGroup(title: "New windows") {
                SettingRow(title: "Open new windows") {
                    Picker("", selection: setting(\.newWindowPlacement)) {
                        Text("Next to focused").tag(NewWindowPlacement.afterFocused)
                        Text("At the end").tag(NewWindowPlacement.end)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                SettingRow(title: "Opening width", subtitle: store.config.useOwnWidth ? "Each window keeps the width it opens with." : nil) {
                    Picker("", selection: setting(\.defaultWidth)) {
                        ForEach(store.config.widthPresets.sorted() + [1.0], id: \.self) { (v: Double) in Text(percent(v)).tag(v) }
                    }
                    .labelsHidden().frame(width: 110).disabled(store.config.useOwnWidth)
                }
                ToggleRow(title: "Keep the width each window opens with", isOn: setting(\.useOwnWidth))
                ToggleRow(title: "Keep each window's original height", subtitle: "Windows sit at the top and keep the height they opened with.", isOn: setting(\.keepOriginalHeight))
                ToggleRow(title: "Float fixed-size windows", subtitle: "Calculator, dialogs and settings windows stay free.", divider: false, isOn: setting(\.floatFixedSizeWindows))
            }

            SettingsGroup(title: "Scrolling", footer: "⌃⌥C centres the focused window once, whatever this is set to.") {
                SettingRow(title: "Centre the focused window") {
                    Picker("", selection: setting(\.centerMode)) {
                        Text("Never").tag(CenterMode.never)
                        Text("If it won't fit").tag(CenterMode.onOverflow)
                        Text("Always").tag(CenterMode.always)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                }
                SettingRow(title: "When windows don't fill the screen", divider: false) {
                    Picker("", selection: setting(\.sparse)) {
                        Text("Start left").tag(SparseAlignment.left)
                        Text("Centre").tag(SparseAlignment.center)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
            }

            SettingsGroup(title: "Preset widths", footer: "⌃⌥R steps through the widths you pick here.") {
                HStack(spacing: 6) {
                    ForEach(candidates, id: \.self) { (v: Double) in
                        let on = store.config.widthPresets.contains { abs($0 - v) < 0.001 }
                        ChipToggle(title: percent(v), on: on) {
                            var p = store.config.widthPresets.filter { abs($0 - v) > 0.001 }
                            if !on { p.append(v) }
                            if !p.isEmpty { store.config.widthPresets = p.sorted() }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }

            SettingsGroup(title: "Tabbed columns") {
                SliderRow(title: "Tab bar height", value: setting(\.tabBarHeight), range: 22...40, step: 1, divider: false) { "\(Int($0)) pt" }
            }
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @ObservedObject private var store = SettingsStore.shared

    private var borderColor: Binding<Color> {
        Binding<Color>(get: { Color(nsColor: NSColor(hex: SettingsStore.shared.config.borderColor) ?? NSColor.systemBlue) },
                       set: { (c: Color) in SettingsStore.shared.config.borderColor = NSColor(c).hexString })
    }

    private let swatches = ["#7B4FD6", "#4F8CFF", "#34C759", "#FF9F0A", "#FF375F", "#64D2FF", "#FFFFFF"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LivePreview(appearance: true)

            SettingsGroup(title: "Focus border") {
                ToggleRow(title: "Draw a border around the focused window", isOn: setting(\.focusBorder))
                SettingRow(title: "Colour") {
                    HStack(spacing: 8) {
                        ForEach(swatches, id: \.self) { (hex: String) in
                            swatch(hex)
                        }
                        ColorPicker("", selection: borderColor, supportsOpacity: false).labelsHidden()
                    }
                }
                .disabled(!store.config.focusBorder)
                .opacity(store.config.focusBorder ? 1 : 0.5)
                SliderRow(title: "Thickness", value: setting(\.borderWidth), range: 1...10, step: 1) { "\(Int($0)) pt" }
                    .disabled(!store.config.focusBorder)
                SliderRow(title: "Corner radius", value: setting(\.borderRadius), range: 0...28, step: 1, divider: false) { "\(Int($0)) pt" }
                    .disabled(!store.config.focusBorder)
            }

            SettingsGroup(title: "Dimming") {
                ToggleRow(title: "Dim the windows you're not using", isOn: setting(\.dimUnfocused))
                SliderRow(title: "Amount", value: setting(\.dimAmount), range: 0.05...0.6, divider: false) { percent($0) }
                    .disabled(!store.config.dimUnfocused)
            }

            SettingsGroup(title: "Strip map", footer: "While the map is showing, click a tile to jump to that window or drag tiles to reorder.") {
                ToggleRow(title: "Flash it when the strip scrolls", isOn: setting(\.showIndicatorOnScroll))
                SettingRow(title: "Show it while I hold") {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) { KeyCap(label: "⌃", size: .small); KeyCap(label: "⌥", size: .small) }
                        Toggle("", isOn: setting(\.showIndicatorOnHold)).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                SettingRow(title: "Position", divider: false) {
                    Picker("", selection: setting(\.indicatorPosition)) {
                        Text("Bottom").tag(IndicatorPosition.bottom)
                        Text("Top").tag(IndicatorPosition.top)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let selected = store.config.borderColor.uppercased() == hex
        return Button { store.config.borderColor = hex } label: {
            Circle().fill(Color(nsColor: NSColor(hex: hex) ?? .white))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.7 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var filter = ""

    var body: some View {
        let conflicts = store.config.conflicts()
        VStack(alignment: .leading, spacing: 18) {
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
                Label("Taken by another app: \(HotkeyCenter.shared.failed.map { KeyboardLayout.label($0) }.joined(separator: ", "))",
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

// MARK: - Trackpad

struct TrackpadPane: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var checks: [SetupCheck] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                TrackpadIllustration(fingers: store.config.swipeFingers)
                Spacer()
            }
            SettingsGroup(title: "Swipe") {
                ToggleRow(title: "Swipe to scroll the strip", isOn: setting(\.swipeEnabled))
                SettingRow(title: "Fingers") {
                    Picker("", selection: setting(\.swipeFingers)) { Text("Three").tag(3); Text("Four").tag(4) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
                ToggleRow(title: "Natural direction", subtitle: "Windows follow your fingers, like scrolling a page.", isOn: setting(\.swipeNatural))
                SettingRow(title: "Sensitivity", divider: false) {
                    HStack(spacing: 8) {
                        Text("Low").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: setting(\.swipeSensitivity), in: 0.4...2.5).frame(width: 200)
                        Text("High").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if let c = checks.first(where: { $0.id == "swipe" }) {
                SetupCheckCard(check: c) { checks = MacSetup.run() }
            }
            if !TrackpadWatcher.shared.isAvailable {
                Label("This Mac's trackpad driver isn't available, so swipes are off.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            SettingsGroup(title: "Mouse", footer: "Focus follows the mouse only for windows that are fully on screen, so the strip never jumps while you point.") {
                SettingRow(title: "Scroll the strip while holding") {
                    HStack(spacing: 8) {
                        HStack(spacing: 3) { KeyCap(label: "⌃", size: .small); KeyCap(label: "⌥", size: .small) }
                        Toggle("", isOn: setting(\.scrollWheelWithModifiers)).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                ToggleRow(title: "Focus follows the mouse", divider: false, isOn: setting(\.focusFollowsMouse))
            }
        }
        .onAppear { checks = MacSetup.run() }
        .onChange(of: store.config.swipeFingers) { _ in checks = MacSetup.run() }
    }
}

// MARK: - App rules

struct AppsPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Float keeps an app's windows free on top of the strip. Ignore leaves the app alone completely.")
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
            SettingsGroup(title: "Rules") {
                if store.config.appRules.isEmpty {
                    SettingRow(title: "No rules yet", divider: false) { EmptyView() }
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
                    Text("Tile").tag(AppBehavior.tile)
                    Text("Float").tag(AppBehavior.float)
                    Text("Ignore").tag(AppBehavior.ignore)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Picker("", selection: ruleBinding(rule.bundleID, \.width)) {
                    Text("Default").tag(Double?.none)
                    ForEach([0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1.0], id: \.self) { (v: Double) in Text(percent(v)).tag(Double?.some(v)) }
                }
                .labelsHidden().frame(width: 92)
                .disabled(rule.behavior != .tile)
                Button { store.config.appRules.removeAll { $0.bundleID == rule.bundleID } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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

// MARK: - Displays

struct DisplaysPane: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ForEach(Displays.current(), id: \.uuid) { (d: Display) in
                    displayCard(d)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("Send the focused window to the next display with").font(.system(size: 12)).foregroundStyle(.secondary)
                CommandKeys(command: .moveToNextDisplay, size: .small)
            }
        }
    }

    private func displayCard(_ d: Display) -> some View {
        let on = !store.config.excludedDisplays.contains(d.uuid)
        let aspect = CGFloat(d.frame.h / max(1, d.frame.w))
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.85))
                Wallpaper().clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).padding(5).opacity(on ? 1 : 0.35)
                if d.isMain {
                    Text("MAIN").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.85))).foregroundStyle(Color.black)
                }
            }
            .frame(width: 160, height: 160 * aspect)
            VStack(spacing: 2) {
                Text(d.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(Int(d.frame.w)) × \(Int(d.frame.h))").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Toggle("Arrange windows here", isOn: Binding<Bool>(get: { on }, set: { (v: Bool) in
                store.config.excludedDisplays.removeAll { $0 == d.uuid }
                if !v { store.config.excludedDisplays.append(d.uuid) }
            }))
            .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Mac Setup

struct MacSetupPane: View {
    @State private var checks: [SetupCheck] = MacSetup.run()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let good = checks.filter { $0.status == .ok }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ProgressRing(value: Double(good), total: Double(max(1, checks.count)), label: "\(good)/\(checks.count)", caption: "look good")
                    .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(good == checks.count ? "Everything looks good." : "A few things to look at.").font(.system(size: 15, weight: .semibold))
                    Text("Only Accessibility is required; the rest just makes Ribbon smoother.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Again") { checks = MacSetup.run() }.buttonStyle(QuietButtonStyle())
            }
            .card(padding: 14, radius: 14)
            ForEach(checks) { c in SetupCheckCard(check: c) { checks = MacSetup.run() } }
            SettingsGroup(title: "If something looks wrong") {
                SettingRow(title: "Windows jump back after you move them", subtitle: "Another window manager is running, or macOS edge tiling is on.") { EmptyView() }
                SettingRow(title: "A swipe switches desktops instead", subtitle: "macOS uses the same number of fingers; see Trackpad & Mouse.") { EmptyView() }
                SettingRow(title: "Ribbon stopped working after an update", subtitle: "In Privacy & Security → Accessibility, remove Ribbon with – and add it again.", divider: false) { EmptyView() }
            }
        }
        .onReceive(timer) { _ in checks = MacSetup.run() }
    }
}

// MARK: - Automation

struct AutomationPane: View {
    @State private var cliStatus = AutomationPane.cliInstalledPath()
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "URL scheme", footer: "Use these from Shortcuts, Alfred, Keyboard Maestro, a Stream Deck or any script.") {
                codeRow("open -g \"ribbon://focus-right\"")
                codeRow("open -g \"ribbon://cycle-width\"")
                codeRow("open -g \"ribbon://focus-window/<number>\"", divider: false)
            }
            SettingsGroup(title: "Command-line tool", footer: "Try ribbon help, ribbon state (JSON of every strip and window), ribbon config set innerGap 6 or ribbon doctor.") {
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
                SettingRow(title: "Copy diagnostics", subtitle: "Mac Setup results, the current layout and recent log lines. Includes app names and window titles.") {
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
        cliStatus = AutomationPane.cliInstalledPath()
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
        --- Mac Setup
        \(MacSetup.run().map { "\($0.status.symbol) \($0.title): \($0.detail)" }.joined(separator: "\n"))
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
            Text("A scrolling window manager for macOS. Windows sit side by side on an endless strip, so opening one never squeezes the others.")
                .font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            SettingsGroup {
                SettingRow(title: "No account, no telemetry, no network") { Image(systemName: "hand.raised.fill").foregroundStyle(Brand.violet) }
                SettingRow(title: "Never reads what's on your screen") { Image(systemName: "eye.slash.fill").foregroundStyle(Brand.violet) }
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
