import AppKit
import Carbon.HIToolbox
import HavenCore
import SwiftUI

/// State behind the Spotlight-style Quick Search panel.
@MainActor
@Observable
final class QuickSearchModel {
    var text = "" { didSet { refresh() } }
    private(set) var results: [FileItem] = []
    private(set) var chips: [QueryChip] = []
    var selectedIndex = 0
    /// Bumped each time the panel opens so the field grabs focus.
    var focusToken = 0

    func refresh(keepSelection: Bool = false) {
        let previous = selected?.id
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            chips = []
            results = Array(LibraryStore.shared.derived.recents.prefix(12))
        } else {
            let parsed = QueryParser.parse(trimmed, customRoots: AppModel.shared.customRootWords)
            chips = parsed.chips
            results = SearchEngine.search(parsed.query, in: LibraryStore.shared.items, text: LibraryStore.shared.text.lookup, limit: 40)
        }
        if keepSelection, let previous, let i = results.firstIndex(where: { $0.id == previous }) {
            selectedIndex = i
        } else {
            selectedIndex = 0
        }
    }

    var selected: FileItem? { results.indices.contains(selectedIndex) ? results[selectedIndex] : nil }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }
}

final class QuickSearchWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Opens with ⇧⌘Space from any app. ↩ opens, ⌘↩ shows in Haven, ⌥↩ shows in Finder, Esc closes.
@MainActor
final class QuickSearchController: NSObject, NSWindowDelegate {
    static let shared = QuickSearchController()

    let model = QuickSearchModel()
    private var panel: QuickSearchWindow?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.text = ""
        model.refresh()
        model.focusToken += 1
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        removeKeyMonitor()
    }

    private func makePanel() -> QuickSearchWindow {
        let panel = QuickSearchWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.setAccessibilityIdentifier("quicksearch.panel")
        let root = QuickSearchView(model: model, onCommit: { [weak self] mods in self?.commit(mods) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - frame.height * 0.16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { close() }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKey(event) }
            return handled ? nil : event
        }
    }

    /// Returns true when the key was used by Quick Search.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel else { return false }
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            model.move(1)
            return true
        case kVK_UpArrow:
            model.move(-1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commit(event.modifierFlags)
            return true
        case kVK_Escape:
            close()
            return true
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c",
               let item = model.selected, isFieldEmptySelection(panel) {
                AppModel.shared.copyFiles([item])
                return true
            }
            return false
        }
    }

    /// ⌘C copies the file only when the text field has no selected text.
    private func isFieldEmptySelection(_ panel: NSPanel) -> Bool {
        guard let editor = panel.firstResponder as? NSTextView else { return true }
        return editor.selectedRange().length == 0
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    func commit(_ modifiers: NSEvent.ModifierFlags) {
        guard let item = model.selected else { return }
        close()
        if modifiers.contains(.command) {
            AppModel.shared.showInHaven(item)
        } else if modifiers.contains(.option) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        } else if item.kind == .folder {
            AppModel.shared.bringMainWindowForward()
            AppModel.shared.navigate(to: .folder(item.path))
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}
