import AppKit
import ApplicationServices
import Carbon.HIToolbox
import HavenCore

/// Sends the Open or Save dialog of the app in front to a folder (or file), the way you'd do it by hand:
/// ⇧⌘G (Go to Folder), the path, Return. Works in Finder windows too. Needs Accessibility permission,
/// because it presses keys for you.
@MainActor
enum DialogJump {
    enum Outcome: Equatable {
        case sent
        case needsPermission
        case noDialog(appName: String)
    }

    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that leads to Privacy & Security › Accessibility.
    static func askForPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// - Parameter app: the app that was in front when Quick Search opened.
    static func go(to path: String, in app: NSRunningApplication?) async -> Outcome {
        guard isAllowed else { return .needsPermission }
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return .noDialog(appName: "Haven")
        }
        let isFinder = app.bundleIdentifier == "com.apple.finder"
        guard isFinder || hasDialog(app) else { return .noDialog(appName: app.localizedName ?? "That app") }
        app.activate()
        try? await Task.sleep(for: .milliseconds(180))
        press(CGKeyCode(kVK_ANSI_G), [.maskCommand, .maskShift])
        try? await Task.sleep(for: .milliseconds(420))
        press(CGKeyCode(kVK_ANSI_A), [.maskCommand])
        type(path)
        try? await Task.sleep(for: .milliseconds(160))
        press(CGKeyCode(kVK_Return), [])
        return .sent
    }

    /// The front window is an Open/Save panel, or has one attached as a sheet.
    static func hasDialog(_ app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        return looksLikeDialog(window as! AXUIElement, depth: 0)
    }

    private static func looksLikeDialog(_ element: AXUIElement, depth: Int) -> Bool {
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        let identifier = string(element, kAXIdentifierAttribute)?.lowercased() ?? ""
        if role == kAXSheetRole as String { return true }
        if subrole == kAXDialogSubrole as String || subrole == kAXSystemDialogSubrole as String { return true }
        if identifier.contains("open-panel") || identifier.contains("save-panel") || identifier.contains("savepanel") || identifier.contains("openpanel") {
            return true
        }
        guard depth < 2 else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return false }
        return list.prefix(40).contains { looksLikeDialog($0, depth: depth + 1) }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode (any language, no keyboard layout surprises), a few characters per event.
    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in KeyText.chunks(text) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Text split into UTF-16 pieces small enough for one key event (macOS takes up to 20 per event).
enum KeyText {
    static func chunks(_ text: String, size: Int = 16) -> [[UniChar]] {
        let units = Array(text.utf16)
        var out: [[UniChar]] = []
        var i = 0
        while i < units.count {
            var end = min(i + size, units.count)
            // Never split a character that takes two UTF-16 units.
            if end < units.count, UTF16.isTrailSurrogate(units[end]) { end -= 1 }
            out.append(Array(units[i..<end]))
            i = end
        }
        return out
    }
}
