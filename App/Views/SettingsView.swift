import AppKit
import HavenCore
import SwiftUI

struct SettingsView: View {
    private var prefs: Prefs { .shared }

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FoldersSettings()
                .tabItem { Label("Folders", systemImage: "folder") }
            QuickSearchSettings()
                .tabItem { Label("Quick Search", systemImage: "command") }
            TextSettings()
                .tabItem { Label("Text", systemImage: "text.viewfinder") }
            CleanupSettingsView()
                .tabItem { Label("Clean Up", systemImage: "sparkles") }
            AISettings()
                .tabItem { Label("AI", systemImage: "waveform.and.magnifyingglass") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 470)
        .environment(\.theme, Theme(look: prefs.look))
        .preferredColorScheme(prefs.appearance.colorScheme)
    }
}

private struct GeneralSettings: View {
    @State private var loginOn = LoginItem.isEnabled

    var body: some View {
        @Bindable var prefs = Prefs.shared
        Form {
            Section("Look") {
                Picker("Style", selection: $prefs.look) {
                    ForEach(Look.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Card size") {
                    Slider(value: $prefs.cardSize, in: 110...320) {
                        Text("Card size")
                    } minimumValueLabel: {
                        Image(systemName: "square.grid.3x3").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "square.grid.2x2").font(.caption)
                    }
                    .labelsHidden()
                }
            }
            Section("Behaviour") {
                Picker("Double-click a file to", selection: $prefs.doubleClick) {
                    ForEach(DoubleClickAction.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show latest downloads in the menu bar", isOn: $prefs.showMenuBarExtra)
                Toggle("Open Haven when you log in", isOn: Binding(get: { loginOn }, set: { on in
                    loginOn = LoginItem.set(on) ? on : LoginItem.isEnabled
                }))
            }
            Section {
                Button("Show Welcome Tour Again") {
                    AppModel.shared.replayOnboarding()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FoldersSettings: View {
    @State private var access: [String: FolderAccess] = [:]
    private var store: LibraryStore { .shared }

    var body: some View {
        @Bindable var prefs = Prefs.shared
        Form {
            Section {
                ForEach(prefs.roots) { root in
                    HStack {
                        Image(systemName: root.symbol).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(root.name)
                            Text(tildePath(root.path)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if access[root.path] == .denied {
                            Button("Allow…") { Permissions.openFilesAndFoldersSettings() }.buttonStyle(.link)
                        }
                        if !root.isStandard {
                            Button {
                                prefs.customRoots.removeAll { $0 == root.path }
                                restart()
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Stop indexing this folder")
                        }
                        Toggle("", isOn: Binding(
                            get: { !prefs.disabledRoots.contains(root.id) },
                            set: { on in
                                if on { prefs.disabledRoots.remove(root.id) } else { prefs.disabledRoots.insert(root.id) }
                                restart()
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            } header: {
                Text("Haven indexes these folders")
            } footer: {
                Text("Haven skips hidden files, app bundles' insides and build folders like node_modules.")
            }
            Section {
                HStack {
                    Button("Add Folder…") { addFolder() }
                    Spacer()
                    Button("Rescan Now") { store.rescan() }
                    Button("Full Disk Access…") { Permissions.openFullDiskAccessSettings() }
                        .help("Optional. Only needed for folders macOS protects beyond Desktop, Documents and Downloads.")
                }
                if let last = store.lastScan {
                    Text("\(HavenFormat.count(store.derived.fileCount, "file")) indexed · last scan \(HavenFormat.ago(last))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            for root in Prefs.shared.roots where root.isProtected {
                access[root.path] = await Permissions.request(root.path)
            }
        }
    }

    private func restart() {
        store.restartWatching()
        store.rescan()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Haven"
        if panel.runModal() == .OK {
            for url in panel.urls where !Prefs.shared.customRoots.contains(url.path) {
                Prefs.shared.customRoots.append(url.path)
            }
            restart()
        }
    }
}

private struct QuickSearchSettings: View {
    var body: some View {
        @Bindable var prefs = Prefs.shared
        Form {
            Section {
                Toggle("Enable Quick Search", isOn: $prefs.quickSearchEnabled)
                    .onChange(of: prefs.quickSearchEnabled) { _, _ in HavenAppDelegate.applyHotKey() }
                LabeledContent("Shortcut") {
                    ShortcutRecorder()
                }
                .disabled(!prefs.quickSearchEnabled)
            } footer: {
                Text("Opens a search panel over any app. ↩ opens the file, ⌘↩ shows it in Haven, ⌥↩ shows it in Finder, ⌘C copies it, and ⌃↩ sends an app's Open or Save dialog there.")
            }
            Section {
                Button("Open Quick Search Now") { QuickSearchController.shared.show() }
                LabeledContent("Open/Save dialog jump") {
                    if DialogJump.isAllowed {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { AppModel.shared.bringMainWindowForward(); AppModel.shared.showDialogJumpHelp = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TextSettings: View {
    private var store: LibraryStore { .shared }

    var body: some View {
        @Bindable var prefs = Prefs.shared
        Form {
            Section {
                Picker("Read text in", selection: $prefs.ocrScope) {
                    ForEach(OCRScope.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.ocrScope) { _, scope in store.text.enqueue(store.items, scope: scope) }
                Toggle("Look for look-alike photos when checking duplicates", isOn: $prefs.findSimilarPhotos)
            } footer: {
                Text("Text recognition uses Apple's Vision framework on this Mac. Nothing is uploaded. PDFs and documents are always read.")
            }
            Section {
                LabeledContent("Files read", value: HavenFormat.count(store.text.readCount, "file"))
                if store.text.isWorking {
                    ProgressView(value: Double(store.text.processed), total: Double(max(1, store.text.total))) {
                        Text("Reading \(store.text.processed) of \(store.text.total)…").font(.caption)
                    }
                }
                Button("Forget Text and Read Again") {
                    store.text.clearCache()
                    store.text.enqueue(store.items, scope: prefs.ocrScope)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CleanupSettingsView: View {
    var body: some View {
        @Bindable var prefs = Prefs.shared
        Form {
            Section("Clean Up suggestions") {
                Stepper("Old installers: older than \(prefs.cleanup.installerAgeDays) days", value: $prefs.cleanup.installerAgeDays, in: 1...365)
                Stepper("Forgotten downloads: unopened for \(prefs.cleanup.forgottenDays) days", value: $prefs.cleanup.forgottenDays, in: 7...730, step: 7)
                Stepper("Old screenshots: older than \(prefs.cleanup.screenshotAgeDays) days", value: $prefs.cleanup.screenshotAgeDays, in: 1...365)
                Stepper("Unused apps: unopened for \(prefs.cleanup.unusedAppDays) days", value: $prefs.cleanup.unusedAppDays, in: 14...730, step: 7)
            }
            .onChange(of: prefs.cleanup) { _, _ in LibraryStore.shared.rederive() }
            Section {
                ForEach(AutoRule.allCases) { rule in
                    Toggle(isOn: Binding(
                        get: { prefs.enabledRules.contains(rule) },
                        set: { on in if on { prefs.enabledRules.insert(rule) } else { prefs.enabledRules.remove(rule) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.title)
                            Text(rule.detail(prefs.ruleSettings)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Stepper("Installer age for the rule: \(prefs.ruleSettings.installerDays) days", value: $prefs.ruleSettings.installerDays, in: 7...365)
                Stepper("Archive downloads after \(prefs.ruleSettings.archiveDays) days", value: $prefs.ruleSettings.archiveDays, in: 7...365, step: 7)
                HStack {
                    Text("Screenshots folder")
                    Spacer()
                    Text(tildePath(prefs.ruleSettings.screenshotFolder)).foregroundStyle(.secondary)
                    Button("Choose…") { chooseScreenshotFolder() }
                }
                Button("Run Rules Now") { RulesRunner.shared.runIfDue(force: true) }
                    .disabled(prefs.enabledRules.isEmpty)
            } header: {
                Text("Automatic rules")
            } footer: {
                Text("Off by default. Everything a rule does is listed in Activity and can be undone.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            Prefs.shared.ruleSettings.screenshotFolder = url.path
        }
    }
}

private struct AboutSettings: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Haven").font(.system(size: 28, weight: .bold, design: theme.headingDesign))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                .foregroundStyle(.secondary)
            Text("A friendlier home for your files. Big thumbnails, plain-English search, text in images, duplicates and clean-up. Built for your Mac; nothing ever leaves it.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .foregroundStyle(.secondary)
            HStack {
                Button("Keyboard Shortcuts") { AppModel.shared.showShortcuts = true; AppModel.shared.bringMainWindowForward() }
                Button("Welcome Tour") { AppModel.shared.replayOnboarding() }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// ⌘/ — every shortcut on one page.
struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private var prefs: Prefs { .shared }

    private var groups: [(String, [(String, String)])] {
        [
            ("Anywhere", [(prefs.hotKey.display, "Quick Search"), ("⌃↩", "In Quick Search: go there in an Open/Save dialog"),
                          ("⌥⌘S", "Shelf"), ("⇧⌘T", "File Tools")]),
            ("Finding", [("⌘F", "Search"), ("⌘[  ⌘]", "Back / Forward"), ("⇧⌘H", "Home"), ("⇧⌘J", "Downloaded From"),
                         ("⇧⌘D", "Duplicates"), ("⇧⌘K", "Clean Up"), ("⌥⌘L", "Downloads")]),
            ("Files", [("Space  ⌘Y", "Quick Look"), ("Double-click", "Large preview"), ("↩  ⌘↓  ⌘O", "Open"),
                       ("⌘↑", "Enclosing folder"), ("⌘A", "Select all"), ("⇧ + arrows", "Extend selection"),
                       ("Type a name", "Jump to a file"), ("⌘I", "Inspector"), ("⌘C", "Copy files"), ("⌘V", "Paste into this folder"),
                       ("⌘R", "Rename"), ("⇧⌘C", "Copy text"), ("⌥⌘C", "Copy path"), ("⇧⌘R", "Show in Finder"),
                       ("⌘⌫", "Move to Trash"), ("⌘Z", "Undo")]),
            ("View", [("⌘1  ⌘2", "Grid / List"), ("⌘+  ⌘−", "Bigger / Smaller cards"), ("⌃⌘T", "Switch look"), ("⌘,", "Settings")]),
            ("Music", [("⌥⌘P", "Play / Pause"), ("⌥⌘←  ⌥⌘→", "Previous / Next")]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(alignment: .top, spacing: 30) {
                // Files has the most keys: it gets a column of its own.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(groups.filter { $0.0 != "Files" }.enumerated()), id: \.offset) { _, g in group(g) }
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(groups.filter { $0.0 == "Files" }.enumerated()), id: \.offset) { _, g in group(g) }
                }
            }
        }
        .padding(24)
        .frame(width: 680)
        .accessibilityIdentifier("shortcuts.sheet")
    }

    private func group(_ g: (String, [(String, String)])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(g.0.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(g.1.enumerated()), id: \.offset) { _, pair in
                HStack {
                    KeyCaps(keys: pair.0).frame(minWidth: 96, alignment: .leading)
                    Text(pair.1)
                }
            }
        }
    }
}

/// Examples of what the search understands.
struct SearchTipsView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(String, String)] = [
        ("Kinds", "pdfs · photos · screenshots · videos · music · documents · spreadsheets · zips · apps · .psd · png"),
        ("Dates", "today · yesterday · last week · this month · past 3 days · in march · since 2023 · older than a year"),
        ("Sizes", "over 5 MB · under 100 KB · between 1 and 2 GB · big (100 MB+) · huge (1 GB+)"),
        ("Sources", "from gmail · from whatsapp · from chatgpt · from canva · airdrop · from example.com"),
        ("Places", "in downloads · on desktop · in documents · in pictures"),
        ("Tags & words", "#work · \"exact phrase\" · any word, matched in names and in text inside files"),
        ("Order", "largest · newest · oldest"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("What you can type").font(.title2.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Mix and match: “photos from whatsapp last month over 2 MB”.").foregroundStyle(.secondary)
            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.0).font(.headline)
                    Text(tip.1).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

/// The on-device AI features: the Whisper model for transcription, translation and summaries.
private struct AISettings: View {
    @Environment(\.theme) private var theme
    private var models: WhisperModels { .shared }

    var body: some View {
        Form {
            Section {
                ForEach(WhisperModel.allCases) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.title)").fontWeight(.medium)
                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if models.installed.contains(model) {
                            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                            Button("Remove") { models.remove(model) }
                        } else if models.downloading == model {
                            ProgressView(value: models.progress).frame(width: 90)
                            Button("Stop") { models.cancelDownload() }
                        } else {
                            Button("Download") { models.download(model) }.disabled(models.downloading != nil)
                        }
                    }
                }
            } header: {
                Text("Transcription (Whisper)")
            } footer: {
                Text("Whisper is OpenAI's open-source speech model (MIT licence), run by whisper.cpp. Audio never leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Translation") {
                if #available(macOS 15.0, *) {
                    Label("Uses the languages built into macOS. It may ask to download a language the first time.", systemImage: "checkmark.circle")
                } else {
                    Label("Needs macOS 15 or later.", systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
            }
            Section("Summaries") {
                if let reason = Summarizer.unavailableReason {
                    Label(reason, systemImage: "xmark.circle").foregroundStyle(.secondary)
                } else {
                    Label("Apple Intelligence makes summaries on this Mac.", systemImage: "checkmark.circle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { models.refresh() }
    }
}
