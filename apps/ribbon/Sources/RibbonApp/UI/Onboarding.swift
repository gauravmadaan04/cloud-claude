#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()
    static let stepCount = 7

    enum InputMode: String, CaseIterable { case click = "Click", keyboard = "Keyboard" }

    @Published var step = 0
    @Published var input: InputMode = .click

    func go(_ s: Int, animated: Bool = true) {
        let target = max(0, min(OnboardingModel.stepCount - 1, s))
        if animated { withAnimation(Brand.spring) { step = target } } else { step = target }
    }
}

private struct TourStep {
    let title: String
    let symbol: String
}

private let tourSteps: [TourStep] = [
    TourStep(title: "Welcome", symbol: "sparkles"),
    TourStep(title: "Permission", symbol: "lock.shield"),
    TourStep(title: "The menu bar", symbol: "menubar.rectangle"),
    TourStep(title: "The basics", symbol: "square.grid.2x2"),
    TourStep(title: "Power tools", symbol: "wand.and.stars"),
    TourStep(title: "Make it yours", symbol: "paintbrush"),
    TourStep(title: "Ready", symbol: "flag.checkered"),
]

// MARK: - The tour window

struct OnboardingView: View {
    var finish: () -> Void
    @ObservedObject private var model = OnboardingModel.shared
    @State private var trusted = AXPermission.isTrusted
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                ZStack {
                    stepView
                        .id(model.step)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 36)
                .padding(.top, 36)
                .clipped()
                footer
            }
        }
        .frame(width: 880, height: 620)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                AuroraBackdrop(intensity: 0.45)
            }
            .ignoresSafeArea()
        )
        .tint(Brand.violet)
        .onReceive(poll) { _ in trusted = AXPermission.isTrusted }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case 0: WelcomeStep()
        case 1: PermissionStep()
        case 2: MenuBarStep()
        case 3: BasicsStep()
        case 4: PowerToolsStep()
        case 5: MakeItYoursStep()
        default: ReadyStep(finish: finish)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                    .shadow(color: Brand.violet.opacity(0.35), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ribbon").font(.system(size: 18, weight: .bold))
                    Text("Welcome tour").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 48)
            .padding(.bottom, 26)

            ForEach(tourSteps.indices, id: \.self) { i in
                stepRow(i)
            }
            Spacer()
            Label("About two minutes", systemImage: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(
            Rectangle().fill(.ultraThinMaterial)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1) }
                .ignoresSafeArea()
        )
    }

    private func stepRow(_ i: Int) -> some View {
        let current = i == model.step
        let done = i < model.step
        return Button {
            model.go(i)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(current ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(done ? 0.0 : 0.07)))
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(Color.green)
                    } else {
                        Image(systemName: tourSteps[i].symbol).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(current ? Color.white : Color.secondary)
                    }
                }
                Text(tourSteps[i].title)
                    .font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(current ? Brand.violet.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Step \(model.step + 1) of \(tourSteps.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if model.step > 0 {
                Button("Back") { model.go(model.step - 1) }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if model.step < tourSteps.count - 1 {
                Button(model.step == 0 ? "Get Started" : (model.step == 1 && !trusted ? "Skip for Now" : "Continue")) { model.go(model.step + 1) }
                    .buttonStyle(BrandButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { finish() } label: { Label("Tidy My Workspace", systemImage: "sparkles") }
                    .buttonStyle(BrandButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}

// MARK: - Shared pieces

private struct StepTitle: View {
    var eyebrow: String? = nil
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Brand.gradient)
            }
            Text(title).font(.system(size: 30, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 14.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureChip: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.gradient)
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75))
    }
}

/// How to do something: keycaps for the keyboard, a short phrase for the mouse.
private struct HowTo: View {
    let keys: [String]
    let mouse: String
    @ObservedObject private var model = OnboardingModel.shared

    var body: some View {
        Group {
            if model.input == .keyboard && !keys.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { (pair: (offset: Int, element: String)) in
                        KeyCap(label: pair.element, size: .small)
                    }
                }
            } else {
                Label(mouse, systemImage: "cursorarrow.click").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 24, alignment: .leading)
    }
}

/// One feature with a little looping demo.
private struct FeatureCard<Demo: View>: View {
    let title: String
    let keys: [String]
    let mouse: String
    @ViewBuilder var demo: Demo
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            demo.frame(maxWidth: .infinity)
                .scaleEffect(hover ? 1.03 : 1)
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HowTo(keys: keys, mouse: mouse)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(hover ? 0.16 : 0.07)))
        .animation(Brand.snappy, value: hover)
        .onHover { hover = $0 }
    }
}

private struct InputSwitch: View {
    @ObservedObject private var model = OnboardingModel.shared
    var body: some View {
        Picker("", selection: $model.input) {
            Label("Click", systemImage: "cursorarrow.click").tag(OnboardingModel.InputMode.click)
            Label("Keyboard", systemImage: "keyboard").tag(OnboardingModel.InputMode.keyboard)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 210)
    }
}

/// A mini preview without the Dock, sized for cards.
private func mini(_ start: Board, every: Double = 1.4, style: PreviewStyle = PreviewStyle(grip: false, showDock: false),
                  _ script: [(inout Board) -> Void]) -> some View {
    ScriptedBoard(start: start, script: script, every: every, style: style)
}

// MARK: - 1 Welcome

struct WelcomeStep: View {
    @State private var settled = false
    private let pile: [WindowID: Rect] = [
        1: Rect(x: 160, y: 150, w: 760, h: 540), 2: Rect(x: 340, y: 210, w: 760, h: 540),
        3: Rect(x: 520, y: 270, w: 760, h: 540),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(eyebrow: "Welcome to Ribbon", title: "Windows that arrange themselves.",
                      subtitle: "Open a window and it takes its place. Close one and the others fill the space. No dragging, no resizing.")
            ZStack(alignment: .bottomTrailing) {
                BoardPreview(board: demoBoard(3), loose: settled ? [:] : pile)
                    .frame(maxWidth: 520)
                Button {
                    settled = false
                    settle()
                } label: {
                    Label("Again", systemImage: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(QuietButtonStyle())
                .padding(12)
                .opacity(settled ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                FeatureChip(symbol: "square.grid.2x2", text: "Grid · Columns · Scrolling")
                FeatureChip(symbol: "square.stack.3d.up", text: "Stacks when full")
                FeatureChip(symbol: "cursorarrow.click", text: "Click or keys")
            }
        }
        .onAppear { settle() }
    }

    private func settle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { settled = true }
        }
    }
}

// MARK: - 2 Permission

struct PermissionStep: View {
    @State private var trusted = AXPermission.isTrusted
    @State private var showHelp = false
    @State private var pulse = false
    @State private var loginOn = LoginItem.isEnabled
    @State private var taken = HotkeyCenter.shared.failedCommands
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "One permission", title: "Let Ribbon arrange your windows.",
                      subtitle: "macOS asks once. Switch Ribbon on in Accessibility and the tour comes right back.")
            mockSettings
            HStack(spacing: 12) {
                if trusted {
                    StatusPill(kind: .good, text: "Access granted. You're all set.")
                } else {
                    Button {
                        AXPermission.prompt()
                        AXPermission.openSettings()
                    } label: {
                        Label("Open Accessibility Settings", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(BrandButtonStyle(large: true))
                    StatusPill(kind: .waiting, text: "Waiting for access")
                }
                Spacer()
            }
            VStack(spacing: 0) {
                checkRow(symbol: "power", colors: BadgeColors.green, title: "Open at login", detail: "Ribbon starts with your Mac.") {
                    Toggle("", isOn: Binding<Bool>(get: { loginOn }, set: { (on: Bool) in
                        LoginItem.set(on)
                        loginOn = LoginItem.isEnabled
                    })).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                Divider().padding(.leading, 48)
                checkRow(symbol: "keyboard", colors: taken.isEmpty ? BadgeColors.blue : BadgeColors.orange,
                         title: taken.isEmpty ? "Shortcuts are free" : "\(taken.count) shortcut\(taken.count == 1 ? " is" : "s are") taken",
                         detail: taken.isEmpty ? "No other app is using Ribbon's keys." : "Another app uses: \(taken.prefix(3).map(\.title).joined(separator: ", "))") {
                    if taken.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                    } else {
                        Button("Change") { UIHub.shared.openSettings(tab: SettingsPane.shortcuts.rawValue) }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .frame(maxWidth: 520)
            if !trusted {
                DisclosureGroup(isExpanded: $showHelp) {
                    Text("In Privacy & Security → Accessibility, click **+**, open **Applications** and choose **Ribbon**. After installing a newer version, select Ribbon, click **–**, then add it again.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Text("Ribbon isn't in the list?").font(.system(size: 12.5, weight: .medium))
                }
                .frame(maxWidth: 520)
            }
            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in
            let now = AXPermission.isTrusted
            taken = HotkeyCenter.shared.failedCommands
            if now != trusted {
                withAnimation(Brand.spring) { trusted = now }
                if now {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    NSApp.activate(ignoringOtherApps: true)   // back from System Settings to the tour
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            // Open at login is on unless you turn it off.
            if !SettingsStore.shared.config.hasCompletedOnboarding, !LoginItem.isEnabled, !LoginItem.needsApproval {
                LoginItem.set(true)
                loginOn = LoginItem.isEnabled
            }
        }
    }

    private func checkRow<Trailing: View>(symbol: String, colors: [Color], title: String, detail: String,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, colors: colors, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// A tiny replica of the System Settings row to switch on.
    private var mockSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                Text("Accessibility").font(.system(size: 14, weight: .bold))
                Spacer()
                IconBadge(symbol: "hand.raised.fill", colors: BadgeColors.blue, size: 20)
                Text("Privacy & Security").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            Divider()
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Ribbon").font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("", isOn: .constant(trusted)).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Brand.violet.opacity(trusted ? 0 : (pulse ? 0.9 : 0.25)), lineWidth: 2)
                    )
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .frame(maxWidth: 520)
    }
}

// MARK: - 3 The menu bar

/// The menu bar panel, animated: a click on a layout picture rearranges the screen.
struct MenuBarStep: View {
    @State private var choice = 2
    private let timer = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()
    private let choices = LayoutChoice.all.filter { $0.id != "cols4" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "The menu bar", title: "Everything is one click away.",
                      subtitle: "Ribbon lives in the menu bar. Click its icon to see your screen, pick a layout and arrange windows. No shortcuts to learn.")
            HStack(alignment: .top, spacing: 26) {
                mockPanel.frame(width: 300)
                VStack(alignment: .leading, spacing: 16) {
                    tip(1, "Click the Ribbon icon", "It's at the top right of your screen. ⌃⌥Space opens it from the keyboard.")
                    tip(2, "Click a layout picture", "Full, halves, 1 + 2, quarters, columns or scrolling: your windows rearrange at once.")
                    tip(3, "Click or drag in the map", "Click a window to switch to it. Drag one onto another to swap them.")
                    tip(4, "Use the buttons", "Make the main window, focus, float, swap, bigger or smaller: all labelled.")
                }
            }
        }
        .onReceive(timer) { _ in withAnimation(Brand.spring) { choice = (choice + 1) % choices.count } }
    }

    private var mockPanel: some View {
        let c = choices[choice]
        let n = c.kind == .scrolling ? 5 : c.count
        let board = demoBoard(n, capacity: max(1, min(n, 4)), active: c.kind == .scrolling ? 3 : 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ribbon").font(.system(size: 12, weight: .bold))
                    Text("Arranging \(n) windows").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Capsule().fill(Brand.gradient).frame(width: 30, height: 17)
            }
            BoardPreview(board: board, style: PreviewStyle(kind: c.kind, grip: false, showDock: false), cornerRadius: 10)
            HStack(spacing: 4) {
                ForEach(choices) { (o: LayoutChoice) in
                    let on = o.id == c.id
                    LayoutGlyph(kind: o.kind, count: o.count, on: on)
                        .frame(width: 26, height: 17)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        .scaleEffect(on ? 1.08 : 1)
                }
            }
            HStack(spacing: 6) {
                ForEach(["arrow.left", "arrow.right", "crown.fill", "scope", "macwindow.on.rectangle"], id: \.self) { (sym: String) in
                    Image(systemName: sym).font(.system(size: 11, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                }
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A picture of Ribbon's menu bar panel, showing the \(c.title) layout")
    }

    private func tip(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white)
                .frame(width: 26, height: 26).background(Circle().fill(Brand.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 4 The basics

struct BasicsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                StepTitle(eyebrow: "The basics", title: "Everything happens on its own.",
                          subtitle: "When you do want to rearrange, it's one click. Keys are there if you like them.")
                InputSwitch()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                FeatureCard(title: "Automatic tiling", keys: [], mouse: "Just open and close windows") {
                    mini(demoBoard(1), [
                        { _ = $0.add(2, capacity: 3, stackWhenFull: true) }, { _ = $0.add(3, capacity: 3, stackWhenFull: true) },
                        { _ = $0.remove(2) },
                    ])
                }
                FeatureCard(title: "Swap windows", keys: ["⌃", "⌥", "←", "→"], mouse: "Menu bar map: drag one window onto another") {
                    mini(demoBoard(3, active: 1), [{ _ = $0.swap(0, 1) }, { _ = $0.swap(1, 2) }, { _ = $0.swap(2, 0) }])
                }
                FeatureCard(title: "Make it the main one", keys: ["⌃", "⌥", "↩"], mouse: "Menu bar: the crown button") {
                    mini(demoBoard(3, active: 3), [{ _ = $0.makePrimary(2) }])
                }
                FeatureCard(title: "Focus", keys: ["⌃", "⌥", "Z"], mouse: "Menu bar: the Focus button") {
                    mini(demoBoard(3, active: 2), every: 1.6, [{ $0.zoomed = 2 }])
                }
                FeatureCard(title: "Stacks when full", keys: ["⌃", "⌥", "`"], mouse: "Click the grip above the window") {
                    mini(demoBoard(3, active: 1), every: 1.3, [
                        { _ = $0.add(4, capacity: 3, stackWhenFull: true) }, { _ = $0.cycle(tile: 0, 1) }, { _ = $0.cycle(tile: 0, 1) },
                    ])
                }
                FeatureCard(title: "Resize", keys: ["⌃", "⌥", "=", "−"], mouse: "Drag the edge between windows") {
                    mini(demoBoard(2, active: 1), [{ $0.splits.x = 0.66 }, { $0.splits.x = 0.36 }])
                }
            }
        }
    }
}

// MARK: - 5 Power tools

struct PowerToolsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                StepTitle(eyebrow: "Power tools", title: "For when you want more.",
                          subtitle: "All optional. Each one is a single shortcut or a click in the menu bar.")
                InputSwitch()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                FeatureCard(title: "Quick actions", keys: [], mouse: "Rest the pointer on the grip above a window") {
                    mini(demoBoard(3, active: 1), style: PreviewStyle(grip: true, showDock: false), [{ $0.setActive(2) }, { $0.setActive(3) }])
                }
                FeatureCard(title: "No peek", keys: ["⌃", "⌥", "D"], mouse: "Menu bar: No peek") {
                    mini(demoBoard(3, active: 2), style: PreviewStyle(dim: 0.55, showDock: false), [{ $0.setActive(1) }, { $0.setActive(3) }])
                }
                FeatureCard(title: "Window switcher", keys: ["⌥", "⇥"], mouse: "Menu bar: click any window in the map") {
                    mini(demoBoard(3, active: 1), every: 0.9, [{ $0.setActive(2) }, { $0.setActive(3) }])
                }
                FeatureCard(title: "Clean Space", keys: ["⌃", "⌥", "P"], mouse: "Menu bar: Clean Space") {
                    mini(demoBoard(3, active: 2), style: PreviewStyle(cleanSpace: true, grip: false, showDock: false), [{ $0.setActive(1) }])
                }
                FeatureCard(title: "Layouts", keys: ["⌃", "⌥", "⌘", "1–4"], mouse: "Menu bar: click a layout picture") {
                    mini(demoBoard(4, capacity: 4), every: 1.5, [{ _ = $0.fit(capacity: 2) }, { _ = $0.fit(capacity: 3) }])
                }
                FeatureCard(title: "Float a window", keys: ["⌃", "⌥", "F"], mouse: "Menu bar: the Float button") {
                    mini(demoBoard(3, active: 3), [{ _ = $0.remove(3) }])
                }
            }
        }
    }
}

// MARK: - 6 Make it yours

struct MakeItYoursStep: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        let c = store.config
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Make it yours", title: "Pick how it looks.",
                      subtitle: "You can change any of this later from the menu bar or Settings.")
            HStack(alignment: .top, spacing: 22) {
                BoardPreview(board: c.layout == .scrolling ? demoBoard(5, capacity: 5, active: 3)
                                                           : demoBoard(min(c.windowsPerScreen, 4), capacity: min(c.windowsPerScreen, 4)),
                             style: PreviewStyle(config: c))
                    .frame(width: 300)
                VStack(alignment: .leading, spacing: 14) {
                    option("Layout") {
                        segmented([("Grid", "square.grid.2x2", c.layout == .grid, { store.config.layout = .grid }),
                                   ("Columns", "rectangle.split.3x1", c.layout == .columns, { store.config.layout = .columns }),
                                   ("Scrolling", "arrow.left.and.right.square", c.layout == .scrolling, { store.config.layout = .scrolling })])
                    }
                    option("Windows per screen") {
                        segmented((1...4).map { (n: Int) -> (String, String?, Bool, () -> Void) in
                            ("\(n)", nil, c.windowsPerScreen == n, { store.config.windowsPerScreen = n })
                        })
                    }
                    option("Highlight the window in use") {
                        segmented(Highlight.allCases.map { (h: Highlight) -> (String, String?, Bool, () -> Void) in
                            (h.title, nil, c.highlight == h, { store.config.highlight = h })
                        })
                    }
                    option("When a screen is full") {
                        segmented([("Stack", "square.stack.3d.up", c.whenFull == .stack, { store.config.whenFull = .stack }),
                                   ("Float", "macwindow.on.rectangle", c.whenFull == .float, { store.config.whenFull = .float })])
                    }
                }
            }
        }
    }

    private func option<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func segmented(_ items: [(String, String?, Bool, () -> Void)]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { (pair: (offset: Int, element: (String, String?, Bool, () -> Void))) in
                let item = pair.element
                Button(action: item.3) {
                    HStack(spacing: 5) {
                        if let s = item.1 { Image(systemName: s).font(.system(size: 11, weight: .semibold)) }
                        Text(item.0).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Capsule().fill(item.2 ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                    .foregroundStyle(item.2 ? Color.white : Color.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Brand.snappy, value: items.map { $0.2 })
    }
}

// MARK: - 7 Ready

struct ReadyStep: View {
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                SuccessMark(size: 54)
                StepTitle(eyebrow: "Ready", title: "You're all set.",
                          subtitle: "Press Tidy My Workspace and watch your windows fall into place. Everything else is one click away in the menu bar, or press ⌃⌥Space.")
            }
            VStack(spacing: 0) {
                tip(.openMenu, "Open Ribbon's menu from the keyboard", "then 1–4, G C S, arrows")
                tip(.swapRight, "Swap with a neighbour", "⌃⌥ and any arrow")
                tip(.makePrimary, "Make the window you're in the main one", nil)
                tip(.focusMode, "Focus: fill the screen, press again to go back", nil)
                tip(.tabView, "See every window and switch", "Hold ⌥ and tap ⇥")
                tip(.showShortcuts, "Every shortcut, any time", nil, divider: false)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            HStack {
                Spacer()
                Button { finish() } label: { Label("Tidy My Workspace", systemImage: "sparkles") }
                    .buttonStyle(BrandButtonStyle(large: true))
                Spacer()
            }
            Spacer(minLength: 0)
        }
    }

    private func tip(_ c: Command, _ title: String, _ note: String?, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 13))
                if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                CommandKeys(command: c, size: .small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            if divider { Divider().padding(.leading, 14) }
        }
    }
}
#endif
