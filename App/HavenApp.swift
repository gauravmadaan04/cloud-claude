import AppKit
import HavenCore
import SwiftUI

@main
struct HavenApp: App {
    @NSApplicationDelegateAdaptor(HavenAppDelegate.self) private var delegate
    @AppStorage("showMenuBarExtra", store: LaunchOptions.current.defaults) private var showMenuBarExtra = true

    init() {
        LaunchOptions.current.applyReset()
    }

    var body: some Scene {
        Window("Haven", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { HavenCommands() }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView()
        } label: {
            Image(systemName: "house.fill")
                .accessibilityLabel("Haven")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class HavenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let opts = LaunchOptions.current
        guard !opts.isRunningUnitTests else { return }
        #if DEBUG
        if opts.makeFixtures, let root = opts.fixtureRoot {
            if opts.fixtureSet == "tools" { FixtureFactory.makeTools(at: root) } else { FixtureFactory.make(at: root) }
        }
        #endif
        Self.applyHotKey()
        ShortcutRouter.shared.install()
        if Prefs.shared.onboardingDone || opts.skipOnboarding {
            LibraryStore.shared.start()
        }
        RulesRunner.shared.startTimer()
    }

    @MainActor
    static func applyHotKey() {
        let prefs = Prefs.shared
        if prefs.quickSearchEnabled {
            HotKeyCenter.shared.register(prefs.hotKey) { QuickSearchController.shared.toggle() }
        } else {
            HotKeyCenter.shared.unregister()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.bringMainWindowForward() }
        return true
    }
}

struct HavenCommands: Commands {
    private var model: AppModel { .shared }
    private var prefs: Prefs { .shared }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Quick Search…") { QuickSearchController.shared.show() }
        }
        CommandGroup(after: .newItem) {
            Button("Open") { model.open(model.selectedItems) }
                .keyboardShortcut("o")
            Button("Show in Finder") { model.revealInFinder(model.selectedItems) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Quick Look") { model.toggleQuickLook() }
                .keyboardShortcut("y")
            Divider()
            Button("Rename…") { model.rename(model.selectedItems) }
                .keyboardShortcut("r")
                .disabled(model.selectedIDs.isEmpty)
            Menu("Make Shareable") {
                ForEach(ShareNaming.Kind.allCases) { kind in
                    Button(kind.title) { model.makeShareable(kind, model.selectedItems) }
                        .disabled(!ShareNaming.applies(kind, to: model.selectedItems))
                }
            }
            .disabled(model.selectedIDs.isEmpty)
            Button("Add to Shelf") { model.addToShelf(model.selectedItems) }
                .disabled(model.selectedIDs.isEmpty)
            Divider()
            Button("Move to Trash") {
                // In a text field, ⌘⌫ keeps its usual meaning.
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
                    editor.deleteToBeginningOfLine(nil)
                    return
                }
                // Only for the files in the main window, and only when it's the window in front.
                guard let main = AppModel.mainWindow, NSApp.keyWindow === main, main.attachedSheet == nil else { return }
                model.trash(model.selectedItems, reason: "Moved by you", undoManager: main.undoManager)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Text") { model.copyText(model.selectedItems) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Path") { model.copyPaths(model.selectedItems) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Select All Files") { model.selectAll() }
            Button("Paste Files Here") { model.pasteFiles() }
            Menu("Copy List of Files") {
                ForEach(ListExport.Format.allCases) { format in
                    Button(format.title) {
                        let items = model.selectedItems.isEmpty ? model.visibleItems : model.selectedItems
                        if format == .csv { model.exportCSV(items) } else { model.copyList(format, items) }
                    }
                }
            }
            .disabled(model.visibleItems.isEmpty)
        }
        CommandGroup(after: .toolbar) {
            Button("as Grid") { prefs.viewMode = .grid }
                .keyboardShortcut("1")
            Button("as List") { prefs.viewMode = .list }
                .keyboardShortcut("2")
            Divider()
            Button("Bigger Cards") { model.bigger() }
                .keyboardShortcut("+")
            Button("Smaller Cards") { model.smaller() }
                .keyboardShortcut("-")
            Divider()
            Button("Show or Hide Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i")
            Button("Switch Look (Playful / Minimal)") { model.toggleLook() }
                .keyboardShortcut("t", modifiers: [.command, .control])
            Divider()
        }
        CommandMenu("Go") {
            Button("Back") { model.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { model.goForward() }
                .keyboardShortcut("]")
            Divider()
            Button("Search") {
                model.bringMainWindowForward()
                model.searchFocusRequest += 1
            }
            .keyboardShortcut("f")
            Button("Home") { go(.home) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Recents") { go(.recents) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Downloads") { go(.folder((LaunchOptions.current.homeForRoots as NSString).appendingPathComponent("Downloads"))) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
            Button("Downloaded From") { go(.sources) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Duplicates") { go(.duplicates) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Clean Up") { go(.cleanup) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Space") { go(.space) }
            Button("Activity") { go(.activity) }
        }
        CommandGroup(after: .windowArrangement) {
            Button("Shelf") { ShelfController.shared.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandMenu("Tools") {
            ToolsMenuContent()
        }
        CommandMenu("Music") {
            Button("Play / Pause") { MusicPlayer.shared.togglePlayPause() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Next Track") { MusicPlayer.shared.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Track") { MusicPlayer.shared.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Stop") { MusicPlayer.shared.stop() }
        }
        CommandGroup(replacing: .help) {
            Button("Welcome Tour") { model.replayOnboarding() }
            Button("Keyboard Shortcuts") {
                model.bringMainWindowForward()
                model.showShortcuts = true
            }
            .keyboardShortcut("/")
            Button("What Can I Search For?") {
                model.bringMainWindowForward()
                model.showSearchTips = true
            }
        }
    }

    private func go(_ item: SidebarItem) {
        model.bringMainWindowForward()
        model.navigate(to: item)
    }
}
