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

final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()
    @Published var step = 0
}

private struct TourStep {
    let title: String
    let symbol: String
}

private let tourSteps: [TourStep] = [
    TourStep(title: "Welcome", symbol: "sparkles"),
    TourStep(title: "How it works", symbol: "rectangle.split.3x1"),
    TourStep(title: "Permission", symbol: "lock.shield"),
    TourStep(title: "Mac check", symbol: "checkmark.seal"),
    TourStep(title: "Practice", symbol: "keyboard"),
    TourStep(title: "Trackpad", symbol: "hand.draw"),
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
                .padding(.horizontal, 40)
                .padding(.top, 38)
                .clipped()
                footer
            }
        }
        .frame(width: 900, height: 640)
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
        case 1: ConceptStep()
        case 2: PermissionStep()
        case 3: SetupStep()
        case 4: PracticeStep()
        case 5: TrackpadStep()
        default: ReadyStep()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                    .shadow(color: Brand.violet.opacity(0.35), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ribbon").font(.system(size: 18, weight: .bold))
                    Text("Setup").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
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
        .frame(width: 214)
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
            go(i)
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
                Button("Back") { go(model.step - 1) }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            if model.step < tourSteps.count - 1 {
                Button(model.step == 2 && !trusted ? "Skip for Now" : "Continue") { go(model.step + 1) }
                    .buttonStyle(BrandButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Using Ribbon") { finish() }
                    .buttonStyle(BrandButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func go(_ s: Int) {
        withAnimation(Brand.spring) { model.step = max(0, min(tourSteps.count - 1, s)) }
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
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

/// Plays a looping script of strip commands for illustrations.
struct ScriptedStrip: View {
    let start: Strip
    let script: [(inout Strip) -> Void]
    var every: Double = 1.4
    var params: LayoutParams = previewParams()
    var showDock = true
    @State private var strip: Strip?
    @State private var tick = 0

    var body: some View {
        StripPreview(strip: strip ?? start, params: params, showDock: showDock)
            .onReceive(Timer.publish(every: every, on: .main, in: .common).autoconnect()) { _ in
                var s = strip ?? start
                let phase = tick % (script.count + 1)
                if phase == script.count {
                    s = start
                } else {
                    script[phase](&s)
                    s.scroll = Layout.scrollToReveal(s, params)
                }
                tick += 1
                strip = s
            }
    }
}

// MARK: - 1 Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(eyebrow: "Welcome to Ribbon", title: "Your windows, side by side.",
                      subtitle: "Every window becomes a column on one long strip that runs past the edges of the screen. Open as many as you like; nothing gets squeezed.")
            ScriptedStrip(start: demoStrip(count: 6, focus: 0), script: [
                { $0.focusRight() }, { $0.focusRight() }, { $0.cycleWidth(presets: [1.0 / 3, 0.5, 2.0 / 3]) },
                { $0.focusRight() }, { $0.focusRight() }, { $0.focusFirst() },
            ])
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                FeatureChip(symbol: "keyboard", text: "Keyboard first")
                FeatureChip(symbol: "hand.draw", text: "Trackpad swipes")
                FeatureChip(symbol: "square.stack", text: "Stacks & tabs")
                FeatureChip(symbol: "bolt.fill", text: "Native & fast")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 2 How it works

struct ConceptStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "The idea", title: "Three things to know.",
                      subtitle: "That's really all there is to Ribbon.")
            HStack(alignment: .top, spacing: 14) {
                concept(symbol: "rectangle.split.3x1", colors: BadgeColors.indigo, title: "Columns, not a grid",
                        text: "A new window opens next to the one you're using. The others keep their widths.",
                        preview: ScriptedStrip(start: demoStrip(count: 2, focus: 0), script: [
                            { $0.insert(3, width: 0.5, focus: true) }, { $0.insert(4, width: 1.0 / 3, focus: true) },
                        ], every: 1.6, showDock: false))
                concept(symbol: "arrow.left.and.right", colors: BadgeColors.violet, title: "The strip scrolls",
                        text: "Focus a window with ⌃⌥ and an arrow, a swipe or a click, and the strip glides to show it.",
                        preview: ScriptedStrip(start: demoStrip(count: 5, focus: 0), script: [
                            { $0.focusRight() }, { $0.focusRight() }, { $0.focusRight() }, { $0.focusLeft() },
                        ], every: 1.2, showDock: false))
                concept(symbol: "square.stack.3d.up", colors: BadgeColors.pink, title: "Stack, tab and pin",
                        text: "Put windows in one column, flip a stack into tabs, or pin one to the edge of the screen.",
                        preview: ScriptedStrip(start: demoStrip(count: 3, focus: 1), script: [
                            { $0.consume(into: .left) }, { $0.toggleTabbed() }, { $0.toggleTabbed() }, { $0.expel(to: .right) },
                        ], every: 1.5, showDock: false))
            }
        }
    }

    private func concept<P: View>(symbol: String, colors: [Color], title: String, text: String, preview: P) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            preview.frame(maxWidth: .infinity)
            IconBadge(symbol: symbol, colors: colors, size: 30)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 14, radius: 18)
    }
}

// MARK: - 3 Permission

struct PermissionStep: View {
    @State private var trusted = AXPermission.isTrusted
    @State private var showHelp = false
    @State private var pulse = false
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "One permission", title: "Let Ribbon arrange your windows.",
                      subtitle: "macOS asks once. Ribbon only moves and resizes windows; it never reads what's in them, and nothing leaves your Mac.")
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
            if !trusted {
                DisclosureGroup(isExpanded: $showHelp) {
                    Text("In Privacy & Security → Accessibility, click **+**, open **Applications** and choose **Ribbon**. After installing a newer version, select Ribbon, click **–**, then add it again.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Text("Ribbon isn't in the list?").font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: 520)
            }
            Spacer(minLength: 0)
        }
        .onReceive(timer) { _ in
            let now = AXPermission.isTrusted
            if now != trusted {
                withAnimation(Brand.spring) { trusted = now }
                if now { WindowManager.shared.start() }
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true } }
    }

    /// A tiny replica of the System Settings row the user needs to switch on.
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
            .padding(.horizontal, 16).padding(.vertical, 12)
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
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().padding(.leading, 58)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)).frame(width: 30, height: 30)
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)).frame(width: 110, height: 9)
                Spacer()
                Toggle("", isOn: .constant(false)).toggleStyle(.switch).labelsHidden().allowsHitTesting(false).opacity(0.5)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .opacity(0.6)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .frame(maxWidth: 520)
    }
}

// MARK: - 4 Mac check

func checkBadge(_ id: String) -> (String, [Color]) {
    switch id {
    case "ax": return ("hand.raised.fill", BadgeColors.blue)
    case "rivals": return ("rectangle.on.rectangle", BadgeColors.orange)
    case "stage": return ("rectangle.3.group", BadgeColors.violet)
    case "tiling": return ("rectangle.split.2x1", BadgeColors.indigo)
    case "spaces": return ("display.2", BadgeColors.teal)
    case "mru": return ("square.stack.3d.down.right", BadgeColors.gray)
    case "swipe": return ("hand.draw", BadgeColors.pink)
    case "login": return ("power", BadgeColors.green)
    default: return ("gearshape", BadgeColors.gray)
    }
}

struct SetupCheckCard: View {
    let check: SetupCheck
    var onFix: () -> Void

    var body: some View {
        let badge = checkBadge(check.id)
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: badge.0, colors: badge.1, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(check.title).font(.system(size: 13, weight: .semibold))
                    statusIcon
                }
                Text(check.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !check.fixes.isEmpty && check.status != .ok {
                    HStack(spacing: 8) {
                        ForEach(Array(check.fixes.enumerated()), id: \.offset) { i, fix in
                            if i == 0 {
                                Button(fix.title) { run(fix) }.buttonStyle(BrandButtonStyle())
                            } else {
                                Button(fix.title) { run(fix) }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12, radius: 14)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch check.status {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(Color.blue)
        }
    }

    private func run(_ fix: SetupCheck.Fix) {
        fix.action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onFix() }
    }
}

struct SetupStep: View {
    @State private var checks: [SetupCheck] = MacSetup.run()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let good = checks.filter { $0.status == .ok }.count
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                StepTitle(eyebrow: "Mac check", title: "A quick look at your setup.",
                          subtitle: "A few macOS settings and apps can get in Ribbon's way. Fix what you like; only Accessibility is required.")
                ProgressRing(value: Double(good), total: Double(max(1, checks.count)), label: "\(good)/\(checks.count)", caption: "look good")
                    .frame(width: 80, height: 80)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(checks) { c in SetupCheckCard(check: c) { checks = MacSetup.run() } }
                }
                .padding(.bottom, 8)
            }
        }
        .onReceive(timer) { _ in checks = MacSetup.run() }
    }
}

struct ProgressRing: View {
    let value: Double
    let total: Double
    let label: String
    let caption: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(value / total))
                .stroke(Brand.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .animation(Brand.spring, value: value)
    }
}

// MARK: - 5 Practice

struct PracticeStep: View {
    @ObservedObject private var practice = PracticeCenter.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var lesson = 0
    @State private var done = Set<Int>()
    @State private var strip = demoStrip(count: 5, focus: 1)
    @State private var handled = 0
    @State private var pressed = false
    @State private var celebrate = false

    var body: some View {
        let lessons = Essentials.lessons
        let current = lessons[min(lesson, lessons.count - 1)]
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(eyebrow: "Practice", title: "Learn the five essentials.",
                      subtitle: "Press each shortcut. The preview follows along, and so do your real windows.")
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 14) {
                    StripPreview(strip: strip, showDock: false)
                    VStack(spacing: 10) {
                        if done.count == lessons.count {
                            HStack(spacing: 14) {
                                SuccessMark(size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("You've got it.").font(.system(size: 17, weight: .bold))
                                    Text("⌃⌥/ shows every other shortcut whenever you need it.").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(current.headline).font(.system(size: 16, weight: .bold))
                            CommandKeys(command: current.command, size: .large, pressed: pressed, highlighted: celebrate)
                            Text(current.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 14, radius: 16)
                }
                .frame(width: 370)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lessons.indices, id: \.self) { i in lessonRow(i) }
                    Spacer(minLength: 0)
                    if done.count < lessons.count {
                        Button("Skip this one") { advance() }.buttonStyle(.link).font(.system(size: 12))
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

    private func lessonRow(_ i: Int) -> some View {
        let isDone = done.contains(i)
        let isCurrent = i == lesson && !isDone
        return Button {
            withAnimation(Brand.snappy) { lesson = i }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "circle.circle.fill" : "circle"))
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? Color.green : (isCurrent ? Brand.violet : Color.secondary))
                VStack(alignment: .leading, spacing: 5) {
                    Text(Essentials.lessons[i].headline).font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    CommandKeys(command: Essentials.lessons[i].command, size: .small)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isCurrent ? Brand.violet.opacity(0.1) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isCurrent ? Brand.violet.opacity(0.35) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func react(to c: Command) {
        var s = strip
        switch c {
        case .focusLeft: s.focusLeft()
        case .focusRight: s.focusRight()
        case .moveLeft: s.moveColumn(-1)
        case .moveRight: s.moveColumn(1)
        case .cycleWidth: s.cycleWidth(presets: store.config.widthPresets)
        case .cycleWidthBack: s.cycleWidth(presets: store.config.widthPresets, forward: false)
        case .fullWidth: s.toggleFullWidth()
        case .stackLeft: s.consume(into: .left)
        case .stackRight: s.consume(into: .right)
        case .popLeft: s.expel(to: .left)
        case .popRight: s.expel(to: .right)
        case .toggleTabbed: s.toggleTabbed()
        case .focusUp: s.focusVertical(-1)
        case .focusDown: s.focusVertical(1)
        case .focusFirst: s.focusFirst()
        case .focusLast: s.focusLast()
        default: break
        }
        s.scroll = Layout.scrollToReveal(s, previewParams())
        strip = s
        withAnimation(Brand.snappy) { pressed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(Brand.snappy) { pressed = false } }

        let target = Essentials.lessons[lesson].command
        let accepted: Set<Command>
        switch target {
        case .focusRight: accepted = [.focusRight, .focusLeft]
        case .moveLeft: accepted = [.moveLeft, .moveRight]
        case .stackLeft: accepted = [.stackLeft, .stackRight]
        default: accepted = [target]
        }
        if accepted.contains(c) && !done.contains(lesson) {
            withAnimation(Brand.spring) {
                celebrate = true
                done.insert(lesson)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(Brand.spring) { celebrate = false }
                advance()
            }
        }
    }

    private func advance() {
        let n = Essentials.lessons.count
        if let next = (0..<n).first(where: { $0 > lesson && !done.contains($0) }) ?? (0..<n).first(where: { !done.contains($0) }) {
            withAnimation(Brand.spring) { lesson = next }
        }
    }
}

// MARK: - 6 Trackpad

/// A trackpad with fingers sliding left and right.
struct TrackpadIllustration: View {
    let fingers: Int
    @State private var swipe = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.77)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
            HStack(spacing: 14) {
                ForEach(0..<fingers, id: \.self) { _ in
                    Circle()
                        .fill(RadialGradient(colors: [Brand.violet.opacity(0.95), Brand.indigo.opacity(0.7)], center: .center, startRadius: 1, endRadius: 16))
                        .frame(width: 26, height: 26)
                        .shadow(color: Brand.violet.opacity(0.5), radius: 6)
                }
            }
            .offset(x: swipe ? 46 : -46)
            Image(systemName: "arrow.left.and.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.black.opacity(0.25))
                .offset(y: 52)
        }
        .frame(width: 250, height: 160)
        .onAppear { withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { swipe = true } }
    }
}

struct TrackpadStep: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var checks: [SetupCheck] = MacSetup.run()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Trackpad & mouse", title: "Swipe through your windows.",
                      subtitle: "Slide your fingers left or right; the strip follows them, then settles on the nearest window.")
            HStack(alignment: .center, spacing: 24) {
                TrackpadIllustration(fingers: store.config.swipeFingers)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Swipe to scroll the strip", isOn: setting(\.swipeEnabled))
                    Picker("Fingers", selection: setting(\.swipeFingers)) { Text("Three").tag(3); Text("Four").tag(4) }
                        .pickerStyle(.segmented).frame(width: 220)
                    Toggle("Natural direction", isOn: setting(\.swipeNatural))
                    Toggle("Hold ⌃⌥ and scroll a mouse to move the strip", isOn: setting(\.scrollWheelWithModifiers))
                }
                .toggleStyle(.switch)
                .card(padding: 16, radius: 16)
            }
            if let c = checks.first(where: { $0.id == "swipe" }) {
                SetupCheckCard(check: c) { checks = MacSetup.run() }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: store.config.swipeFingers) { _ in checks = MacSetup.run() }
    }
}

// MARK: - 7 Ready

struct ReadyStep: View {
    @State private var login = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                SuccessMark(size: 52)
                StepTitle(title: "Ribbon is ready.", subtitle: "It lives in the menu bar. Everything else is a shortcut away.")
            }
            VStack(alignment: .trailing, spacing: 6) {
                MenuBarStrip(scale: 0.62)
                    .frame(height: 22)
                    .background(Brand.softGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Label("Ribbon's menu is up here", systemImage: "arrow.turn.right.up")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.violet)
                    .padding(.trailing, 70)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tip(.showShortcuts, "Every shortcut", "A cheat sheet, any time.")
                tip(.showStrip, "Strip map", "Or hold ⌃⌥. Click a tile to jump.")
                tip(.toggleFloat, "Float a window", "Takes it off the strip, and back.")
                tip(.toggleTiling, "Pause Ribbon", "Puts every window back on screen.")
            }
            Toggle(isOn: Binding<Bool>(get: { login }, set: { (on: Bool) in
                LoginItem.set(on)
                login = LoginItem.isEnabled
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Ribbon when I log in").font(.system(size: 13, weight: .semibold))
                    Text("Recommended, so your strips are always there.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .card(padding: 14, radius: 14)
            Spacer(minLength: 0)
        }
    }

    private func tip(_ c: Command, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            CommandKeys(command: c, size: .small)
        }
        .card(padding: 12, radius: 14)
    }
}
#endif
