import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (no Accessibility permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?
    private(set) var isRegistered = false
    /// Counts presses, so onboarding can tell the user "that worked".
    private(set) var pressCount = 0

    func register(_ combo: HotKeyCombo, action: @escaping () -> Void) {
        unregister()
        onPress = action
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4856_4E31), id: 1) // 'HVN1'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        isRegistered = false
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.fire() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func fire() {
        pressCount += 1
        NotificationCenter.default.post(name: .havenHotKeyPressed, object: nil)
        onPress?()
    }

    // MARK: Translating key events

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func symbols(_ carbon: UInt32) -> String {
        var s = ""
        if carbon & UInt32(controlKey) != 0 { s += "⌃" }
        if carbon & UInt32(optionKey) != 0 { s += "⌥" }
        if carbon & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbon & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    static func keyName(_ keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return (characters ?? "?").uppercased()
        }
    }

    /// A combo from a key press in the shortcut recorder; nil if it has no modifier (too easy to trigger by accident).
    static func combo(from event: NSEvent) -> HotKeyCombo? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let carbon = carbonModifiers(flags)
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        let isFunctionKey = functionKeys.contains(Int(event.keyCode))
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 || isFunctionKey else { return nil }
        let name = keyName(event.keyCode, characters: event.charactersIgnoringModifiers)
        return HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbon, display: symbols(carbon) + name)
    }
}

extension Notification.Name {
    static let havenHotKeyPressed = Notification.Name("HavenHotKeyPressed")
}
