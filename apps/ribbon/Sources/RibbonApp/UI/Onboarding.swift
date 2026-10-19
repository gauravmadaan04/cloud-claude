#if os(macOS)
import AppKit
import SwiftUI
import RibbonCore

/// Broadcasts commands so the practice step can react to the real shortcuts.
final class PracticeCenter: ObservableObject {
    static let shared = PracticeCenter()
    @Published var last: (command: Command, serial: Int)?
    private var serial = 0
    func received(_ c: Command) {
        serial += 1
        last = (c, serial)
    }
}

// MARK: - A miniature strip, drawn with the real layout engine

struct DemoWindow {
    let title: String
    let symbol: String
    let color: Color
}

let demoWindows: [WindowID: DemoWindow] = [
    1: DemoWindow(title: "Mail", symbol: "envelope.fill", color: Color(red: 0.33, green: 0.56, blue: 0.98)),
    2: DemoWindow(title: "Notes", symbol: "note.text", color: Color(red: 0.98, green: 0.76, blue: 0.24)),
    3: DemoWindow(title: "Safari", symbol: "safari.fill", color: Color(red: 0.27, green: 0.75, blue: 0.86)),
    4: DemoWindow(title: "Terminal", symbol: "terminal.fill", color: Color(red: 0.25, green: 0.27, blue: 0.32)),
    5: DemoWindow(title: "Music", symbol: "music.note", color: Color(red: 0.98, green: 0.36, blue: 0.43)),
    6: DemoWindow(title: "Calendar", symbol: "calendar", color: Color(red: 0.55, green: 0.42, blue: 0.95)),
]

func demoStrip(count: Int = 5) -> Strip {
    var s = Strip()
    let widths = [0.5, 0.5, 2.0 / 3, 1.0 / 3, 0.5, 0.5]
    for i in 1...count { s.insert(WindowID(i), width: widths[i - 1], at: .end, focus: false) }
    s.focusColumn(1)
    s.scroll = Layout.scrollToReveal(s, demoParams)
    return s
}

let demoParams = LayoutParams(screen: Rect(x: 0, y: 0, w: 1200, h: 700), area: Rect(x: 0, y: 26, w: 1200, h: 674),
                              innerGap: 16, outerGap: 16, tabBarHeight: 36)

struct MiniStripView: View {
    var strip: Strip

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / demoParams.screen.w
            let sy = geo.size.height / demoParams.screen.h
            let r = Layout.compute(strip, demoParams)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.38), Color(red: 0.42, green: 0.28, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 26 * sy)
                ForEach(r.placements, id: \.window) { pl in
                    let hiddenTab = strip.columns[pl.column].mode == .tabbed && pl.row != strip.columns[pl.column].active
                    if !hiddenTab {
                        DemoWindowView(demo: demoWindows[pl.window], focused: strip.focusedWindow == pl.window, scale: sx)
                            .frame(width: pl.frame.w * sx, height: pl.frame.h * sy)
                            .offset(x: pl.frame.x * sx, y: pl.frame.y * sy)
                    }
                }
                ForEach(r.tabBars, id: \.column) { tb in
                    HStack(spacing: 3) {
                        ForEach(Array(tb.windows.enumerated()), id: \.offset) { i, wid in
                            Text(demoWindows[wid]?.title ?? "")
                                .font(.system(size: max(8, 22 * sx), weight: .semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoundedRectangle(cornerRadius: 4).fill(i == tb.active ? Color.accentColor : Color.white.opacity(0.25)))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(2)
                    .frame(width: tb.frame.w * sx, height: (tb.frame.h - 4) * sy)
                    .offset(x: r.columnRects[tb.column].x * sx, y: tb.frame.y * sy)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: strip)
        }
        .aspectRatio(demoParams.screen.w / demoParams.screen.h, contentMode: .fit)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

struct DemoWindowView: View {
    let demo: DemoWindow?
    let focused: Bool
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * scale + 3, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach([Color.red, Color.yellow, Color.green], id: \.self) { c in
                        Circle().fill(c.opacity(0.85)).frame(width: max(4, 12 * scale), height: max(4, 12 * scale))
                    }
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity)
                .background((demo?.color ?? .gray).opacity(0.18))
                Spacer()
                Image(systemName: demo?.symbol ?? "macwindow")
                    .font(.system(size: max(12, 70 * scale)))
                    .foregroundColor(demo?.color ?? .gray)
                Text(demo?.title ?? "").font(.system(size: max(9, 26 * scale), weight: .semibold)).foregroundColor(.secondary)
                Spacer()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12 * scale + 3, style: .continuous)
                .strokeBorder(focused ? Color.accentColor : Color.black.opacity(0.1), lineWidth: focused ? 3 : 1)
        )
    }
}

// MARK: - The tour

final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()
    @Published var step = 0
}

struct OnboardingView: View {
    var finish: () -> Void
    @ObservedObject private var model = OnboardingModel.shared
    private var step: Int { model.step }
    private let titles = ["Welcome", "How it works", "Permission", "Mac Setup", "Practice", "Trackpad", "Done"]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: ConceptStep()
                case 2: PermissionStep()
                case 3: SetupStep()
                case 4: PracticeStep()
                case 5: TrackpadStep()
                default: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)

            Divider()
            HStack {
                HStack(spacing: 7) {
                    ForEach(titles.indices, id: \.self) { i in
                        Capsule().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == step ? 22 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.3), value: step)
                Text(titles[step]).font(.callout).foregroundColor(.secondary).padding(.leading, 6)
                Spacer()
                if step > 0 { Button("Back") { go(step - 1) }.keyboardShortcut(.cancelAction) }
                if step < titles.count - 1 {
                    Button(step == 2 && !AXPermission.isTrusted ? "Skip for Now" : "Continue") { go(step + 1) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Using Ribbon") { finish() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 760, height: 560)
    }

    private func go(_ s: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { model.step = s }
    }
}

private struct StepHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).font(.title3).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WelcomeStep: View {
    @State private var strip = demoStrip()
    @State private var tick = 0
    private let timer = Timer.publish(every: 1.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Ribbon").font(.system(size: 32, weight: .bold))
                    Text("Your windows, side by side on an endless strip.").font(.title3).foregroundColor(.secondary)
                }
            }
            MiniStripView(strip: strip).frame(height: 300)
            Text("Opening a window never squeezes the others. The strip simply scrolls to whatever you're working on. This short tour gets you set up and teaches the five shortcuts you'll use most. It takes about two minutes.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).frame(maxWidth: 560)
        }
        .onReceive(timer) { _ in
            tick += 1
            let script: [(inout Strip) -> Void] = [
                { $0.focusRight() }, { $0.focusRight() }, { $0.cycleWidth(presets: [1.0 / 3, 0.5, 2.0 / 3]) },
                { $0.focusRight() }, { $0.focusLeft() }, { $0.focusFirst() },
            ]
            script[tick % script.count](&strip)
            strip.scroll = Layout.scrollToReveal(strip, demoParams)
        }
    }
}

struct ConceptStep: View {
    @State private var strip: Strip = {
        var s = demoStrip(count: 4)
        s.focusColumn(2)
        s.consume(into: .left)
        s.scroll = Layout.scrollToReveal(s, demoParams)
        return s
    }()

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "How Ribbon works", subtitle: "Three ideas, and you know it all.")
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 18) {
                    idea("rectangle.split.3x1", "Columns on a strip",
                         "Every window is a column. New ones open next to the one you're using; the rest keep their widths.")
                    idea("arrow.left.and.right", "The strip scrolls",
                         "Focus a window with ⌃⌥ + arrows, a three-finger swipe or a click, and the strip glides to show it.")
                    idea("square.stack", "Stacks, tabs and pins",
                         "Stack windows in one column, turn a stack into tabs, or pin a window to the screen edge.")
                }
                .frame(width: 330)
                MiniStripView(strip: strip).frame(width: 330)
            }
        }
    }

    private func idea(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundColor(.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PermissionStep: View {
    @State private var trusted = AXPermission.isTrusted
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "Let Ribbon arrange your windows",
                       subtitle: "macOS asks you to allow this once. Ribbon only moves and resizes windows; it never reads what's in them.")
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05))
                if trusted {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundColor(.green)
                        Text("Access granted. You're ready to go.").font(.title3.weight(.semibold))
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        stepRow(1, "Click **Open Accessibility Settings** below.")
                        stepRow(2, "Turn on the switch next to **Ribbon** (enter your password if asked).")
                        stepRow(3, "Come back here. This page notices by itself.")
                        Text("Ribbon isn't in the list? Click **+**, open **Applications**, choose **Ribbon**. After installing a new version, remove Ribbon with **–** and add it again.")
                            .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button {
                            AXPermission.prompt()
                            AXPermission.openSettings()
                        } label: {
                            Label("Open Accessibility Settings", systemImage: "lock.open").padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(26)
                }
            }
            .frame(width: 560, height: 270)
            .animation(.spring(response: 0.4), value: trusted)
        }
        .onReceive(timer) { _ in
            let now = AXPermission.isTrusted
            if now != trusted {
                trusted = now
                if now { WindowManager.shared.start() }
            }
        }
    }

    private func stepRow(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundColor(.white).frame(width: 26, height: 26).background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SetupStep: View {
    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: "Quick Mac check", subtitle: "A few macOS settings and apps can get in Ribbon's way. Fix what you like; nothing here is required.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { MacSetupList() }.padding(18)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
            .frame(maxHeight: 330)
        }
    }
}

struct PracticeStep: View {
    @ObservedObject private var practice = PracticeCenter.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var lesson = 0
    @State private var done = Set<Int>()
    @State private var strip = demoStrip()
    @State private var handled = 0

    var body: some View {
        let lessons = Essentials.lessons
        let current = lessons[min(lesson, lessons.count - 1)]
        VStack(spacing: 14) {
            StepHeader(title: "Learn the five essentials", subtitle: "Press each shortcut. It works on your real windows too.")
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lessons.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            Image(systemName: done.contains(i) ? "checkmark.circle.fill" : (i == lesson ? "circle.inset.filled" : "circle"))
                                .foregroundColor(done.contains(i) ? .green : (i == lesson ? .accentColor : .secondary))
                            Text(lessons[i].headline).fontWeight(i == lesson ? .semibold : .regular)
                            Spacer()
                            Text(combo(lessons[i].command)).font(.system(.callout, design: .rounded).weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(i == lesson ? Color.accentColor.opacity(0.12) : .clear))
                        .onTapGesture { lesson = i }
                    }
                }
                .frame(width: 300)
                VStack(spacing: 12) {
                    MiniStripView(strip: strip).frame(width: 340)
                    VStack(spacing: 6) {
                        Text("Press").foregroundColor(.secondary)
                        Text(combo(current.command)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.accentColor)
                        Text(current.detail).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).frame(width: 330)
                        if lesson < lessons.count - 1 || !done.contains(lesson) {
                            Button("Skip this one") { advance() }.buttonStyle(.link).font(.callout)
                        }
                    }
                }
            }
        }
        .onReceive(practice.$last) { ev in
            guard let ev, ev.serial != handled else { return }
            handled = ev.serial
            react(to: ev.command)
        }
    }

    private func combo(_ c: Command) -> String {
        store.config.combos(for: c).first.map { KeyboardLayout.label($0) } ?? "—"
    }

    private func react(to c: Command) {
        // Mirror the command on the demo strip.
        var s = strip
        switch c {
        case .focusLeft: s.focusLeft()
        case .focusRight: s.focusRight()
        case .moveLeft: s.moveColumn(-1)
        case .moveRight: s.moveColumn(1)
        case .cycleWidth: s.cycleWidth(presets: store.config.widthPresets)
        case .fullWidth: s.toggleFullWidth()
        case .stackLeft: s.consume(into: .left)
        case .stackRight: s.consume(into: .right)
        case .popLeft: s.expel(to: .left)
        case .popRight: s.expel(to: .right)
        case .toggleTabbed: s.toggleTabbed()
        case .focusUp: s.focusVertical(-1)
        case .focusDown: s.focusVertical(1)
        default: break
        }
        s.scroll = Layout.scrollToReveal(s, demoParams)
        strip = s
        let target = Essentials.lessons[lesson].command
        let accepted: Set<Command>
        switch target {
        case .focusRight: accepted = [.focusRight, .focusLeft]
        case .moveLeft: accepted = [.moveLeft, .moveRight]
        case .stackLeft: accepted = [.stackLeft, .stackRight]
        default: accepted = [target]
        }
        if accepted.contains(c) {
            done.insert(lesson)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { advance() }
        }
    }

    private func advance() {
        let n = Essentials.lessons.count
        if let next = (0..<n).first(where: { $0 > lesson && !done.contains($0) }) ?? (0..<n).first(where: { !done.contains($0) }) {
            withAnimation { lesson = next }
        }
    }
}

struct TrackpadStep: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var checks: [SetupCheck] = MacSetup.run()

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Swipe through your windows", subtitle: "Slide fingers left or right on the trackpad and the strip follows, then settles on the nearest window.")
            HStack(spacing: 30) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06)).frame(width: 220, height: 150)
                    HStack(spacing: 10) {
                        ForEach(0..<store.config.swipeFingers, id: \.self) { _ in
                            Circle().fill(Color.accentColor.opacity(0.75)).frame(width: 22, height: 22)
                        }
                    }
                    Image(systemName: "arrow.left.and.right").font(.title).foregroundColor(.secondary).offset(y: 44)
                }
                Form {
                    Toggle("Swipe to scroll the strip", isOn: setting(\.swipeEnabled))
                    Picker("Fingers", selection: setting(\.swipeFingers)) { Text("Three").tag(3); Text("Four").tag(4) }
                        .pickerStyle(.segmented)
                    Toggle("Natural direction", isOn: setting(\.swipeNatural))
                    Toggle("Hold ⌃⌥ and scroll a mouse to move the strip", isOn: setting(\.scrollWheelWithModifiers))
                }
                .formStyle(.grouped)
                .frame(width: 380, height: 210)
            }
            if let c = checks.first(where: { $0.id == "swipe" }) {
                SetupCheckRow(check: c) { checks = MacSetup.run() }.frame(width: 640)
            }
        }
        .onChange(of: store.config.swipeFingers) { _ in checks = MacSetup.run() }
    }
}

struct DoneStep: View {
    @State private var login = LoginItem.isEnabled
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundColor(.green)
            StepHeader(title: "You're all set", subtitle: "Ribbon lives in the menu bar. Look for the three-column icon.")
            VStack(alignment: .leading, spacing: 10) {
                tip("keyboard", "**\(label(.showShortcuts))** shows every shortcut, any time.")
                tip("hand.raised", "Hold **⌃⌥** to see the strip map; click a tile to jump to it.")
                tip("pause.circle", "**\(label(.toggleTiling))** pauses Ribbon and puts every window back on screen.")
                tip("gearshape", "Gaps, widths, colours, shortcuts and app rules are in **Settings**.")
            }
            .frame(width: 520, alignment: .leading)
            Toggle("Open Ribbon automatically when I log in", isOn: Binding(get: { login }, set: { on in
                LoginItem.set(on)
                login = LoginItem.isEnabled
            }))
            .toggleStyle(.switch)
        }
    }

    private func label(_ c: Command) -> String {
        store.config.combos(for: c).first.map { KeyboardLayout.label($0) } ?? ""
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundColor(.accentColor).frame(width: 24)
            Text(text)
        }
    }
}
#endif
