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
        // Browser keys belong to pages that show a grid or list of files.
        let browsing = model.fileListsOnScreen > 0

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
        // Arrows (⇧ to extend) move through the files, unless the sidebar has the keyboard.
        if browsing, mods.subtracting(.shift).isEmpty, let direction = Self.direction(code),
           !(window.firstResponder is NSTableView) {
            return model.moveSelection(direction, extend: mods.contains(.shift))
        }
        // Letters, digits and punctuation without ⌘/⌃/⌥: jump to a file by name.
        if browsing, mods.subtracting(.shift).isEmpty, let chars = event.characters, let scalar = chars.unicodeScalars.first,
           CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains(scalar) {
            return model.typeAhead(chars)
        }

        guard mods == [.command] else { return false }
        switch key {
        case "a":
            guard browsing, !model.visibleItems.isEmpty else { return false }
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

    static func direction(_ keyCode: UInt16) -> AppModel.MoveDirection? {
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    /// A text field has the keyboard, or some read-only text is selected (so ⌘C copies that text).
    static func isEditingText(_ window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if let text = responder as? NSTextView {
            return text.isEditable || text.isFieldEditor || text.selectedRange().length > 0
        }
        return responder is NSTextField
    }
}
