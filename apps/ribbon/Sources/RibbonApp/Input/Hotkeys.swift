#if os(macOS)
import AppKit
import Carbon.HIToolbox
import RibbonCore

/// System-wide shortcuts through Carbon's RegisterEventHotKey: no extra permission needed and
/// keys are matched by physical position, so they work on any keyboard layout.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var commands: [UInt32: Command] = [:]
    private var handlerInstalled = false
    private(set) var failed: [KeyCombo] = []
    private(set) var suspended = false
    var onCommand: ((Command) -> Void)?

    private init() {}

    func apply(_ config: Config) {
        unregisterAll()
        guard !suspended else { return }
        installHandler()
        var nextID: UInt32 = 1
        failed = []
        for (combo, cmd) in config.effectiveBindings() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5242_4E21), id: nextID) // 'RBN!'
            let status = RegisterEventHotKey(combo.keyCode, HotkeyCenter.carbonModifiers(combo.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                commands[nextID] = cmd
            } else {
                failed.append(combo)
                Log.error("Shortcut \(combo) for \(cmd.rawValue) is taken (status \(status))")
            }
            nextID += 1
        }
    }

    /// Lets the shortcut recorder see key presses that are normally swallowed.
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        apply(SettingsStore.shared.config)
    }

    private func unregisterAll() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        commands.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard let cmd = commands[id] else { return }
        DispatchQueue.main.async { self.onCommand?(cmd) }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if st == noErr { HotkeyCenter.shared.fire(hk.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        var c: UInt32 = 0
        if m.contains(.command) { c |= UInt32(cmdKey) }
        if m.contains(.shift) { c |= UInt32(shiftKey) }
        if m.contains(.option) { c |= UInt32(optionKey) }
        if m.contains(.control) { c |= UInt32(controlKey) }
        return c
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var m = Modifiers()
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }
}

/// Names keys the way the user's current keyboard layout prints them.
enum KeyboardLayout {
    private static var cache: [UInt32: String] = [:]
    private static var cachedSource: String?

    static func name(for keyCode: UInt32) -> String? {
        if KeyCode.isLayoutIndependent(keyCode) { return nil }
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        let srcID = (TISGetInputSourceProperty(src, kTISPropertyInputSourceID)).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        }
        if srcID != cachedSource { cache.removeAll(); cachedSource = srcID }
        if let c = cache[keyCode] { return c }
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).uppercased()
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        cache[keyCode] = s
        return s
    }

    static func label(_ combo: KeyCombo) -> String { combo.label { name(for: $0) } }
}
#endif
