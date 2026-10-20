import AppKit
import HavenCore
import SwiftUI

/// First-launch tour: explains Haven, asks for folder access the friendly way, and teaches the main moves.
struct OnboardingView: View {
    enum Page: Int, CaseIterable {
        case welcome, privacy, folders, look, search, quickSearch, menuBar, tour, ready

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .privacy: return "Private"
            case .folders: return "Folders"
            case .look: return "Look"
            case .search: return "Search"
            case .quickSearch: return "Quick Search"
            case .menuBar: return "Menu bar"
            case .tour: return "Tools"
            case .ready: return "Ready"
            }
        }
    }

    @State private var page: Page = .welcome
    @State private var forward = true
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                stepper
                    .padding(.top, 22)
                // The page gets exactly the space between the dots and the buttons, so the buttons never move.
                GeometryReader { geo in
                    ZStack {
                        pageView(page)
                            .id(page)
                            .transition(.asymmetric(
                                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                            ))
                            .frame(maxWidth: 780)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .clipped()
                Divider().opacity(0.5)
                controls
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if theme.isPlayful {
                LinearGradient(colors: [Color(hex: 0xFFB4C6), Color(hex: 0xA7D3FF), Color(hex: 0xC9B6FF)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.12)
                Circle().fill(Color(hex: 0xFFB4C6).opacity(0.22)).frame(width: 420).blur(radius: 80).offset(x: -380, y: -220)
                Circle().fill(Color(hex: 0xA7D3FF).opacity(0.25)).frame(width: 460).blur(radius: 90).offset(x: 420, y: 240)
            }
        }
        .ignoresSafeArea()
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases, id: \.rawValue) { p in
                Capsule()
                    .fill(p.rawValue <= page.rawValue ? theme.accent : Color.primary.opacity(0.12))
                    .frame(width: p == page ? 26 : 8, height: 8)
                    .animation(.spring(duration: 0.35), value: page)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    private var controls: some View {
        HStack {
            if page != .welcome {
                Button("Back") { go(-1) }
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            if page != .ready && page != .welcome {
                Button("Skip Tour") { finish() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.skip")
            }
            Button {
                if page == .ready { finish() } else { go(1) }
            } label: {
                Text(primaryTitle)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(theme.accent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(page == .ready ? "onboarding.finish" : "onboarding.continue")
        }
    }

    private var primaryTitle: String {
        switch page {
        case .welcome: return "Get Started"
        case .folders: return "Continue"
        case .ready: return "Start Exploring"
        default: return "Continue"
        }
    }

    private func go(_ delta: Int) {
        guard let next = Page(rawValue: page.rawValue + delta) else { return }
        if page == .folders && delta > 0 {
            // Start indexing once the user has seen why Haven needs the folders.
            LibraryStore.shared.start()
        }
        forward = delta > 0
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { page = next }
    }

    private func finish() {
        prefs.onboardingDone = true
        LibraryStore.shared.start()
        withAnimation(.easeInOut(duration: 0.35)) { model.showOnboarding = false }
    }

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        switch p {
        case .welcome: WelcomePage()
        case .privacy: PrivacyPage()
        case .folders: FoldersPage()
        case .look: LookPage()
        case .search: SearchDemoPage()
        case .quickSearch: QuickSearchPage()
        case .menuBar: MenuBarPage()
        case .tour: TourPage()
        case .ready: ReadyPage()
        }
    }
}

// MARK: - Pages

private struct PageTitle: View {
    let symbol: String
    let title: String
    let subtitle: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 58, height: 58)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            Text(title)
                .font(.system(size: 27, weight: .bold, design: theme.headingDesign))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding.title")
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomePage: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            VStack(spacing: 10) {
                Text("Welcome to Haven")
                    .font(.system(size: 40, weight: .bold, design: theme.headingDesign))
                    .accessibilityIdentifier("onboarding.title")
                Text("Finder shows you a list of file names.\nHaven shows you your stuff.")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                feature("photo.on.rectangle.angled", "Big thumbnails", "See what's inside every folder")
                feature("text.magnifyingglass", "Plain-English search", "“pdfs from last week” just works")
                feature("sparkles", "Gentle clean-up", "Duplicates, old installers, forgotten downloads")
            }
            .padding(.top, 6)
            Text("This short tour takes about a minute.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(theme.accent)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 200, height: 130)
        .cardStyle(theme, padding: 14)
    }
}

private struct PrivacyPage: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            PageTitle(symbol: "lock.shield", title: "Everything stays on your Mac",
                      subtitle: "Haven has no account and never uploads anything. In fact, it doesn't use the internet at all.")
            VStack(alignment: .leading, spacing: 16) {
                point("eye.slash", "Reading text in screenshots and photos happens on this Mac with Apple's Vision.")
                point("square.on.square", "Duplicate checks compare files right here. Files stored only in iCloud are skipped, so nothing downloads.")
                point("trash", "Haven never deletes anything outright. Files only go to the Trash, and every clean-up can be undone.")
                point("folder", "Haven works alongside Finder. “Show in Finder” is always one click away.")
            }
            .frame(maxWidth: 560)
            .cardStyle(theme, padding: 22)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(theme.accent).frame(width: 26)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FoldersPage: View {
    @Environment(\.theme) private var theme
    @State private var access: [String: FolderAccess] = [:]
    @State private var asking = false
    private var prefs: Prefs { .shared }

    var body: some View {
        let roots = prefs.roots
        let protected = roots.filter(\.isProtected)
        let others = roots.filter { !$0.isProtected }
        VStack(spacing: 18) {
            PageTitle(symbol: "folder.badge.questionmark", title: "Choose what Haven looks at",
                      subtitle: "macOS protects Desktop, Documents and Downloads. Click Allow, then OK when your Mac asks. Haven only reads them to show and search your files.")
            VStack(spacing: 0) {
                ForEach(protected) { root in
                    folderRow(root)
                    if root.id != protected.last?.id { Divider().padding(.leading, 52) }
                }
            }
            .frame(maxWidth: 600)
            .cardStyle(theme, padding: 8)
            HStack(spacing: 8) {
                Text("Also included:").foregroundStyle(.secondary)
                ForEach(others) { root in
                    let on = !prefs.disabledRoots.contains(root.id)
                    Button {
                        if on { prefs.disabledRoots.insert(root.id) } else { prefs.disabledRoots.remove(root.id) }
                    } label: {
                        Label(root.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(on ? 0.07 : 0.03), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .help(on ? "Haven includes \(root.name). Click to leave it out." : "Click to include \(root.name).")
                }
            }
            .font(.callout)
            HStack(spacing: 12) {
                Button {
                    Task { await allowAll(roots) }
                } label: {
                    Label("Allow All", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(asking)
                .accessibilityIdentifier("onboarding.allowAll")
                Button {
                    addFolder()
                } label: {
                    Label("Add Another Folder…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                if access.values.contains(.denied) {
                    Button("Open System Settings") { Permissions.openFilesAndFoldersSettings() }
                        .buttonStyle(.link)
                }
            }
            Text("Change these any time in Settings → Folders.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .task {
            // Folders that don't need permission are checked right away.
            for root in roots where !root.isProtected {
                access[root.path] = Permissions.probe(root.path)
            }
            if LaunchOptions.current.isFixtureMode {
                for root in roots { access[root.path] = Permissions.probe(root.path) }
            }
        }
    }

    private func folderRow(_ root: IndexRoot) -> some View {
        let state = access[root.path] ?? (root.isProtected ? .notAsked : .granted)
        let included = Binding(
            get: { !prefs.disabledRoots.contains(root.id) },
            set: { on in if on { prefs.disabledRoots.remove(root.id) } else { prefs.disabledRoots.insert(root.id) } }
        )
        return HStack(spacing: 14) {
            Image(systemName: root.symbol)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(root.name).font(.headline)
                Text(state == .granted ? tildePath(root.path) : state.label)
                    .font(.caption)
                    .foregroundStyle(state == .denied ? Color.red : Color.secondary)
            }
            Spacer()
            if root.isProtected && state != .granted && state != .missing {
                Button("Allow") { Task { await ask(root) } }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(asking)
                    .accessibilityIdentifier("onboarding.allow.\(root.id)")
            } else if state == .granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Toggle("", isOn: included)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Include \(root.name) in Haven")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func ask(_ root: IndexRoot) async {
        asking = true
        access[root.path] = await Permissions.request(root.path)
        asking = false
    }

    private func allowAll(_ roots: [IndexRoot]) async {
        for root in roots where root.isProtected && access[root.path] != .granted {
            await ask(root)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Haven"
        if panel.runModal() == .OK {
            for url in panel.urls where !prefs.customRoots.contains(url.path) {
                prefs.customRoots.append(url.path)
                access[url.path] = .granted
            }
        }
    }
}

private struct LookPage: View {
    @Environment(\.theme) private var theme
    private var prefs: Prefs { .shared }

    var body: some View {
        @Bindable var prefs = Prefs.shared
        VStack(spacing: 26) {
            PageTitle(symbol: "paintpalette", title: "Pick a look",
                      subtitle: "Playful is colourful. Minimal is black, white and grey. Switch any time with ⌃⌘T.")
            HStack(spacing: 22) {
                ForEach(Look.allCases) { look in
                    LookPreviewCard(look: look, selected: prefs.look == look)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) { prefs.look = look }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(look.title) look")
                        .accessibilityAddTraits(prefs.look == look ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityAction { prefs.look = look }
                        .accessibilityIdentifier("onboarding.look.\(look.rawValue)")
                }
            }
            Picker("Appearance", selection: $prefs.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }
}

private struct LookPreviewCard: View {
    let look: Look
    let selected: Bool

    var body: some View {
        let t = Theme(look: look)
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 10), count: 3), spacing: 10) {
                ForEach(LibraryCategory.allCases) { c in
                    ZStack(alignment: .topLeading) {
                        FolderShape().fill(t.fill(c))
                            .overlay(FolderShape().stroke(look == .minimal ? Color.primary.opacity(0.15) : .clear))
                        Image(systemName: t.symbol(c.symbolName))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(t.tint(c))
                            .padding(.top, 14)
                            .padding(.leading, 9)
                    }
                    .frame(width: 70, height: 52)
                }
            }
            HStack {
                Image(systemName: look.symbol)
                Text(look.title).font(.system(.headline, design: t.headingDesign))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? t.accent : Color.secondary)
            }
        }
        .padding(18)
        .frame(width: 290)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? t.accent : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
        .shadow(color: .black.opacity(selected ? 0.12 : 0.04), radius: selected ? 14 : 6, y: 4)
        .environment(\.theme, t)
    }
}

private struct SearchDemoPage: View {
    @State private var text = "pdfs from last week"
    @Environment(\.theme) private var theme

    private let examples = [
        "pdfs from last week", "screenshots over 5 MB", "photos from whatsapp", "big videos older than a year",
        "downloaded yesterday", "invoice in documents", "#work spreadsheets", "largest files on desktop",
    ]

    var body: some View {
        let parsed = QueryParser.parse(text)
        VStack(spacing: 22) {
            PageTitle(symbol: "text.magnifyingglass", title: "Search the way you talk",
                      subtitle: "Type what you remember. Haven turns it into filters you can see, and also looks at the text inside screenshots, photos and PDFs.")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Try it", text: $text)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .accessibilityIdentifier("onboarding.search.field")
                }
                .padding(12)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                FlowLayout(spacing: 6) {
                    Text("Haven reads:").foregroundStyle(.secondary)
                    if parsed.chips.isEmpty {
                        Text("…").foregroundStyle(.tertiary)
                    }
                    ForEach(parsed.chips) { ChipView(chip: $0).fixedSize() }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .frame(maxWidth: 620)
            .cardStyle(theme, padding: 18)
            VStack(spacing: 8) {
                Text("Tap an example").font(.caption).foregroundStyle(.secondary)
                FlowRow(items: examples) { example in
                    Button(example) { text = example }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: 640)
            }
        }
    }
}

/// Simple wrapping row of buttons.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var centered = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Centre each row.
        var rows: [[(Subviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((s, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            var rx = centered ? bounds.minX + (bounds.width - rowWidth) / 2 : bounds.minX
            let h = row.map { $0.1.height }.max() ?? 0
            for (s, size) in row {
                s.place(at: CGPoint(x: rx, y: y), proposal: ProposedViewSize(size))
                rx += size.width + spacing
            }
            y += h + spacing
        }
    }
}

private struct QuickSearchPage: View {
    @Environment(\.theme) private var theme
    @State private var tried = false
    @State private var recording = false
    private var prefs: Prefs { .shared }

    var body: some View {
        VStack(spacing: 24) {
            PageTitle(symbol: "command", title: "Quick Search, from any app",
                      subtitle: "Press the shortcut wherever you are. Type, then ↩ to open, ⌘↩ to show it in Haven, or ⌥↩ to show it in Finder.")
            HStack(spacing: 10) {
                ForEach(Array(keyParts.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .frame(minWidth: 58, minHeight: 58)
                        .padding(.horizontal, key.count > 1 ? 14 : 0)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                        .shadow(color: .black.opacity(0.1), radius: 0, y: 3)
                }
            }
            Group {
                if tried {
                    Label("It works! Press Esc to close the panel.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("onboarding.hotkey.ok")
                } else {
                    Label("Try it now: press \(prefs.hotKey.display)", systemImage: "hand.point.up.left")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            HStack(spacing: 10) {
                Text("Prefer a different shortcut?").foregroundStyle(.secondary)
                ShortcutRecorder()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .havenHotKeyPressed)) { _ in
            withAnimation { tried = true }
        }
    }

    private var keyParts: [String] {
        let display = prefs.hotKey.display
        var parts: [String] = []
        var rest = Substring(display)
        while let c = rest.first, "⌃⌥⇧⌘".contains(c) {
            parts.append(String(c))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }
}

/// Click, then press a new key combination.
struct ShortcutRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?
    private var prefs: Prefs { .shared }

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : prefs.hotKey.display)
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .help("Click, then press a new shortcut. Esc cancels.")
        .accessibilityIdentifier("shortcut.recorder")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                if event.keyCode == 53 { stop(); return true } // Esc
                if let combo = HotKeyCenter.combo(from: event) {
                    prefs.hotKey = combo
                    stop()
                    return true
                }
                NSSound.beep()
                return true
            }
            return handled ? nil : event
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        HavenAppDelegate.applyHotKey()
    }
}

private struct MenuBarPage: View {
    @Environment(\.theme) private var theme
    @State private var loginOn = LoginItem.isEnabled
    private var prefs: Prefs { .shared }

    var body: some View {
        @Bindable var prefs = Prefs.shared
        VStack(spacing: 26) {
            PageTitle(symbol: "menubar.arrow.up.rectangle", title: "Your latest downloads, one click away",
                      subtitle: "Haven's menu bar icon lists the ten newest downloads with thumbnails. Drag any of them straight into Mail, Slack or Figma.")
            VStack(spacing: 0) {
                Toggle(isOn: $prefs.showMenuBarExtra) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Haven in the menu bar").font(.headline)
                        Text("Latest downloads, Quick Search and Settings").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .accessibilityIdentifier("onboarding.menubar")
                Divider()
                Toggle(isOn: Binding(get: { loginOn }, set: { on in loginOn = LoginItem.set(on) ? on : LoginItem.isEnabled })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Haven when you log in").font(.headline)
                        Text("So Quick Search and the menu bar are always ready").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
            }
            .frame(maxWidth: 520)
            .cardStyle(theme, padding: 6)
        }
    }
}

private struct TourPage: View {
    @Environment(\.theme) private var theme

    struct Feature: Identifiable {
        let symbol: String, title: String, text: String, keys: String
        var id: String { title }
    }

    private let features: [Feature] = [
        Feature(symbol: "text.magnifyingglass", title: "Search", text: "Plain English, with filters you can see", keys: "⌘F"),
        Feature(symbol: "text.quote", title: "Copy text from images", text: "Hover a screenshot or PDF and click Copy Text", keys: "⇧⌘C"),
        Feature(symbol: "arrow.down.circle", title: "Downloaded From", text: "Downloads grouped by Gmail, WhatsApp, ChatGPT…", keys: "⇧⌘J"),
        Feature(symbol: "square.on.square", title: "Duplicates", text: "Identical files and look-alike photos", keys: "⇧⌘D"),
        Feature(symbol: "sparkles", title: "Clean Up", text: "Old installers, forgotten downloads, big old videos", keys: "⇧⌘K"),
        Feature(symbol: "eye", title: "Preview", text: "Space for Quick Look, double-click for a big preview", keys: "Space"),
        Feature(symbol: "info.circle", title: "Inspector", text: "Size, camera, duration, where it came from", keys: "⌘I"),
        Feature(symbol: "bookmark", title: "Saved searches", text: "Keep a search in the sidebar; it updates itself", keys: "Save"),
        Feature(symbol: "arrow.uturn.backward", title: "Undo anything", text: "Trashed by mistake? Undo, or see Activity", keys: "⌘Z"),
        Feature(symbol: "pencil", title: "Smart rename", text: "Name many files at once, even from the text inside", keys: "⌘R"),
        Feature(symbol: "tray.full", title: "Shelf", text: "Gather files from anywhere, drag them out together", keys: "⌥⌘S"),
        Feature(symbol: "macwindow", title: "Open/Save jump", text: "In Quick Search, send a file dialog to a folder", keys: "⌃↩"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("A few things to try")
                    .font(.system(size: 27, weight: .bold, design: theme.headingDesign))
                    .accessibilityIdentifier("onboarding.title")
                Text("Everything is also in the menus. See all shortcuts any time with ⌘/.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(features) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: f.symbol).font(.body.weight(.semibold)).foregroundStyle(theme.accent)
                            Text(f.title).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            KeyCaps(keys: f.keys)
                        }
                        Text(f.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .cardStyle(theme, padding: 11)
                }
            }
            .frame(maxWidth: 760)
            Text("Replay this tour from Help → Welcome Tour.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ReadyPage: View {
    @Environment(\.theme) private var theme
    private var store: LibraryStore { .shared }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.accent)
                .symbolEffect(.bounce, value: store.hasLoaded)
            Text("You're all set")
                .font(.system(size: 36, weight: .bold, design: theme.headingDesign))
                .accessibilityIdentifier("onboarding.title")
            Group {
                if store.isScanning || !store.hasLoaded {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Haven has found \(HavenFormat.count(store.scanCount, "file")) so far…")
                    }
                } else {
                    Text("Haven found \(HavenFormat.count(store.derived.fileCount, "file")) (\(ByteSize.format(store.derived.totalBytes))).")
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            Text("Reading text in images carries on quietly in the background.")
                .foregroundStyle(.tertiary)
        }
    }
}
