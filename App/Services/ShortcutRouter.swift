import AppKit
import HavenCore

/// Finder's everyday keys for the file browser, wherever keyboard focus happens to be in the main window:
/// ⌘A select all, ⌘C copy files, ⌘V paste files into the open folder, Space Quick Look, ↩ / ⌘↓ / ⌘O open,
/// ⌘↑ enclosing folder, ⌘Y Quick Look. While you type in a text field every key keeps its usual text meaning.
@MainActor
final class ShortcutRouter {
    static let shared = ShortcutRouter()
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let used = MainActor.assumeIsolated { ShortcutRouter.shared.handle(event) }
            return used ? nil : event
        }
    }

    /// True when the event was used.
    func handle(_ event: NSEvent) -> Bool {
        let model = AppModel.shared
        guard let window = event.window, window === AppModel.mainWindow, window.isKeyWindow,
              window.attachedSheet == nil, NSApp.modalWindow == nil, !model.showOnboarding else { return false }
        if Self.isEditingText(window) { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        let code = event.keyCode
        if mods.isEmpty && code == 49 { // Space
            if model.isPreviewing { model.closePreview(); return true }
            guard !model.selectedIDs.isEmpty || model.quickLookURL != nil else { return false }
            model.toggleQuickLook()
            return true
        }
        if (mods.isEmpty && (code == 36 || code == 76)) || (mods == .command && code == 125) { // ↩, Enter, ⌘↓
            let selected = model.selectedItems
            guard !selected.isEmpty, !model.isPreviewing else { return false }
            if selected.count == 1, let one = selected.first, mods.isEmpty { model.activate(one) } else { model.open(selected) }
            return true
        }
        if mods == .command && code == 126 { // ⌘↑
            return model.goToEnclosingFolder()
        }

        guard mods == [.command] else { return false }
        switch key {
        case "a":
            guard !model.visibleItems.isEmpty else { return false }
            model.selectAll()
            return true
        case "c":
            let selected = model.selectedItems
            guard !selected.isEmpty else { return false }
            model.copyFiles(selected)
            return true
        case "v":
            return model.pasteFiles()
        case "y":
            guard !model.selectedIDs.isEmpty || model.quickLookURL != nil else { return false }
            model.toggleQuickLook()
            return true
        default:
            return false
        }
    }

    /// A text field or text view has the keyboard.
    static func isEditingText(_ window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if let text = responder as? NSTextView { return text.isEditable || text.isFieldEditor }
        return responder is NSTextField
    }
}
