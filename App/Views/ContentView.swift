import HavenCore
import QuickLook
import SwiftUI

struct ContentView: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private var prefs: Prefs { .shared }

    var body: some View {
        let theme = Theme(look: prefs.look)
        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 320)
            } detail: {
                DetailView()
                    .modifier(SuggestionsOverlay())
                    .inspector(isPresented: $model.showInspector) {
                        InspectorView()
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
                    }
                    .toolbar { MainToolbar() }
                    .navigationTitle(windowTitle)
            }
            .toolbar(model.showOnboarding ? .hidden : .visible, for: .windowToolbar)

            if model.previewItem != nil {
                PreviewOverlay()
                    .zIndex(2)
            }
            if model.showOnboarding {
                OnboardingView()
                    .zIndex(3)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast, !model.showOnboarding {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .quickLookPreview($model.quickLookURL, in: model.visibleURLs)
        .sheet(isPresented: $model.showShortcuts) { ShortcutsHelpView() }
        .sheet(isPresented: $model.showSearchTips) { SearchTipsView() }
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(prefs.appearance.colorScheme)
        .frame(minWidth: 960, minHeight: 620)
        .background(WindowFitter())
        .onAppear {
            #if DEBUG
            FocusProbe.start()
            #endif
            model.openWindowAction = openWindow
            model.openSettingsAction = openSettings
        }
        .animation(.easeInOut(duration: 0.2), value: model.previewItem?.id)
        .animation(.easeInOut(duration: 0.3), value: model.showOnboarding)
    }

    private var windowTitle: String {
        if model.isSearching { return "Search" }
        return model.selection?.title ?? "Haven"
    }
}

struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            NavButtons()
        }
        ToolbarItem(placement: .principal) {
            SearchField()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            MiniPlayerView()
            ViewOptions()
        }
    }
}

struct NavButtons: View {
    @Bindable private var model = AppModel.shared

    var body: some View {
        HStack(spacing: 2) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack && !model.isSearching)
                .help("Back (⌘[)")
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("Forward (⌘])")
        }
    }
}

/// The search box in the toolbar. Focus is tracked through AppKit (SwiftUI's focus state doesn't follow
/// toolbar fields), and its look never changes with focus so the toolbar item isn't rebuilt mid-click.
struct SearchField: View {
    @Bindable private var model = AppModel.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search, like “pdfs from last week”", text: $model.searchText)
                .textFieldStyle(.plain)
                .onSubmit { model.focusResultsRequest += 1 }
                .onKeyPress(.downArrow) {
                    model.focusResultsRequest += 1
                    return .handled
                }
                .onExitCommand {
                    if model.isPreviewing {
                        model.closePreview()
                        return
                    }
                    model.searchText = ""
                    SearchFieldBridge.shared.resign()
                }
                .accessibilityIdentifier("search.field")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityIdentifier("search.clear")
            } else {
                Button { model.showSearchTips = true } label: {
                    Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("What can I type?")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .background(SearchFieldAnchor())
        .frame(minWidth: 200, idealWidth: 340, maxWidth: 420)
        .onChange(of: model.searchFocusRequest) { _, _ in SearchFieldBridge.shared.focus() }
    }
}

/// Talks to the AppKit text field behind the toolbar search box: focuses it on ⌘F and reports when it has
/// keyboard focus. The toolbar lives outside the window's content view, so an editable field there is ours.
@MainActor
final class SearchFieldBridge: NSObject {
    static let shared = SearchFieldBridge()

    private weak var window: NSWindow?
    private var updateToken: NSObjectProtocol?
    private var responderObservation: NSKeyValueObservation?
    private var isFocused = false

    func attach(window: NSWindow) {
        guard window !== self.window else { return }
        self.window = window
        if let updateToken { NotificationCenter.default.removeObserver(updateToken) }
        updateToken = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        guard let window else { return }
        let editing = (window.firstResponder as? NSText)?.delegate as? NSTextField
        let focused = window.isKeyWindow && editing.map { isToolbarField($0, in: window) } == true
        guard focused != isFocused else { return }
        isFocused = focused
        if focused {
            AppModel.shared.searchFieldFocused = true
        } else {
            // Let a click on a suggestion land before the list goes away.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                if !self.isFocused { AppModel.shared.searchFieldFocused = false }
            }
        }
    }

    private func isToolbarField(_ field: NSTextField, in window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        return field.window === window && !field.isDescendant(of: content)
    }

    private func toolbarField(in window: NSWindow) -> NSTextField? {
        guard let frame = window.contentView?.superview else { return nil }
        var stack: [NSView] = [frame]
        while let view = stack.popLast() {
            if view === window.contentView { continue }
            if let field = view as? NSTextField, field.isEditable { return field }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    func focus() {
        guard let window = window ?? NSApp.mainWindow, let field = toolbarField(in: window) else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    /// Gives up keyboard focus, but only if the search field has it.
    func resign() {
        guard let window else { return }
        let editing = (window.firstResponder as? NSText)?.delegate as? NSTextField
        if let editing, isToolbarField(editing, in: window) {
            window.makeFirstResponder(nil)
        }
    }
}

/// Invisible view behind the search box that tells `SearchFieldBridge` which window it's in.
private struct SearchFieldAnchor: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SearchFieldBridge.shared.attach(window: window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ nsView: Anchor, context: Context) {}
}

/// Recent searches and ideas under the toolbar field while it's focused and empty.
struct SuggestionsOverlay: ViewModifier {
    @Bindable private var model = AppModel.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if model.searchFieldFocused && model.searchText.isEmpty && !model.showOnboarding && model.previewItem == nil {
                    SearchSuggestionsView()
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .animation(.snappy(duration: 0.2), value: model.searchFieldFocused && model.searchText.isEmpty)
    }
}

struct ViewOptions: View {
    @Bindable private var model = AppModel.shared
    private var prefs: Prefs { .shared }

    var body: some View {
        @Bindable var prefs = Prefs.shared
        Picker("View", selection: $prefs.viewMode) {
            Image(systemName: "square.grid.2x2").tag(ViewMode.grid).help("Grid (⌘1)")
            Image(systemName: "list.bullet").tag(ViewMode.list).help("List (⌘2)")
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("toolbar.viewMode")

        Menu {
            if model.isSearching {
                Button { model.searchSortOverride = nil } label: {
                    if model.searchSortOverride == nil { Label("Best Match", systemImage: "checkmark") } else { Text("Best Match") }
                }
                Divider()
            }
            ForEach(FileSortOrder.allCases) { order in
                Button {
                    if model.isSearching { model.searchSortOverride = order } else { prefs.sortOrder = order }
                } label: {
                    let active = model.isSearching ? model.searchSortOverride == order : prefs.sortOrder == order
                    if active { Label(order.title, systemImage: "checkmark") } else { Text(order.title) }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort")

        Button {
            model.toggleLook()
        } label: {
            Label("Switch Look", systemImage: prefs.look == .playful ? "paintpalette" : "circle.lefthalf.filled")
        }
        .help(prefs.look == .playful ? "Playful look. Click for Minimal (⌃⌘T)" : "Minimal look. Click for Playful (⌃⌘T)")
        .accessibilityIdentifier("toolbar.look")

        Button {
            model.showInspector.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help("Show details (⌘I)")
        .accessibilityIdentifier("toolbar.inspector")
    }
}

struct MiniPlayerView: View {
    private var player: MusicPlayer { .shared }

    var body: some View {
        if let current = player.current {
            HStack(spacing: 8) {
                Group {
                    if let art = player.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.title.isEmpty ? current.baseName : player.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    ProgressView(value: player.duration > 0 ? min(1, player.position / player.duration) : 0)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
                .frame(width: 96)
                Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                    .help("Play/Pause (⌥⌘P)")
                    .accessibilityIdentifier("player.toggle")
                Button { player.next() } label: { Image(systemName: "forward.fill") }.help("Next (⌥⌘→)")
                Button { player.stop() } label: { Image(systemName: "xmark") }.help("Stop")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .contextMenu {
                Button("Previous Track") { player.previous() }
                Button("Next Track") { player.next() }
            }
        }
    }
}

/// On first appearance, shrinks/moves the window so it fits the screen's visible area.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { SearchFieldBridge.shared.attach(window: window) }
            guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            var frame = window.frame
            guard !visible.contains(frame) else { return }
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            window.setFrame(frame, display: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#if DEBUG
/// Test-only breadcrumbs: every change of key window and first responder, written to a file the UI tests print.
@MainActor
enum FocusProbe {
    static let path = "/private/tmp/haven-focus.log"
    private static var last = ""
    private static var timer: Timer?
    private static let started = Date()

    static func start() {
        guard LaunchOptions.current.isFixtureMode, timer == nil else { return }
        try? FileManager.default.removeItem(atPath: path)
        write("probe started")
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = describe()
                if now != last {
                    last = now
                    write(now)
                }
            }
        }
    }

    private static func describe() -> String {
        guard let window = NSApp.keyWindow else { return "no key window" }
        let title = window.title.isEmpty ? String(describing: type(of: window)) : window.title
        guard let r = window.firstResponder else { return "key: \(title) · responder: nil" }
        var name = String(describing: type(of: r))
        if let tv = r as? NSTextView, tv.isFieldEditor, let owner = tv.delegate as? NSView {
            name += " editing \(type(of: owner)) [\(owner.accessibilityIdentifier())]"
        } else if let v = r as? NSView {
            if !v.accessibilityIdentifier().isEmpty { name += " [\(v.accessibilityIdentifier())]" }
            name += " in \(type(of: v.superview ?? v))"
        }
        return "key: \(title) · responder: \(name)"
    }

    static func write(_ line: String) {
        guard LaunchOptions.current.isFixtureMode else { return }
        let stamp = String(format: "%7.2f ", Date().timeIntervalSince(started))
        let data = Data((stamp + line + "\n").utf8)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
#endif
