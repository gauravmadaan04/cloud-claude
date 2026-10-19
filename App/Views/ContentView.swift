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
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
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

struct SearchField: View {
    @Bindable private var model = AppModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search in plain English, like “pdfs from last week”", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand {
                    model.searchText = ""
                    focused = false
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
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(focused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)))
        .frame(width: 440)
        .onChange(of: model.searchFocusRequest) { _, _ in focused = true }
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.title.isEmpty ? current.baseName : player.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    ProgressView(value: player.duration > 0 ? min(1, player.position / player.duration) : 0)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }
                .frame(width: 120)
                Button { player.previous() } label: { Image(systemName: "backward.fill") }.help("Previous (⌥⌘←)")
                Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                    .help("Play/Pause (⌥⌘P)")
                    .accessibilityIdentifier("player.toggle")
                Button { player.next() } label: { Image(systemName: "forward.fill") }.help("Next (⌥⌘→)")
                Button { player.stop() } label: { Image(systemName: "xmark") }.help("Stop")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
        }
    }
}
