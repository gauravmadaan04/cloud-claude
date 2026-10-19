#if os(macOS)
import AppKit
import ApplicationServices
import RibbonCore

/// Private but long-stable call used by every macOS window manager to get a window's number.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

/// A small, typed wrapper around AXUIElement.
struct AXElement: Hashable {
    let ref: AXUIElement

    init(_ ref: AXUIElement) { self.ref = ref }

    static func app(_ pid: pid_t) -> AXElement { AXElement(AXUIElementCreateApplication(pid)) }
    static let systemWide = AXElement(AXUIElementCreateSystemWide())

    static func == (a: AXElement, b: AXElement) -> Bool { CFEqual(a.ref, b.ref) }
    func hash(into h: inout Hasher) { h.combine(CFHash(ref)) }

    // MARK: Reading

    func raw(_ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(ref, attr as CFString, &v)
        return err == .success ? v : nil
    }

    func string(_ attr: String) -> String? { raw(attr) as? String }
    func bool(_ attr: String) -> Bool? { (raw(attr) as? NSNumber)?.boolValue }

    func element(_ attr: String) -> AXElement? {
        guard let v = raw(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXElement(v as! AXUIElement)
    }

    func elements(_ attr: String) -> [AXElement] {
        guard let arr = raw(attr) as? [AnyObject] else { return [] }
        return arr.compactMap { o in
            CFGetTypeID(o) == AXUIElementGetTypeID() ? AXElement(o as! AXUIElement) : nil
        }
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String { string(kAXTitleAttribute) ?? "" }
    var isMinimized: Bool { bool(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { bool("AXFullScreen") ?? false }
    var isEnabled: Bool { bool(kAXEnabledAttribute) ?? true }
    var isMain: Bool { bool(kAXMainAttribute) ?? false }
    var windows: [AXElement] { elements(kAXWindowsAttribute) }
    var focusedWindow: AXElement? { element(kAXFocusedWindowAttribute) }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(ref, &p)
        return p
    }

    var windowID: WindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(ref, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    var position: CGPoint? {
        guard let v = raw(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = raw(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    var frame: Rect? {
        guard let p = position, let s = size else { return nil }
        return Rect(x: p.x, y: p.y, w: s.width, h: s.height)
    }

    func isSettable(_ attr: String) -> Bool {
        var b: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(ref, attr as CFString, &b) == .success && b.boolValue
    }

    // MARK: Writing

    @discardableResult
    func setPosition(_ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(ref, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    func setSize(_ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(ref, kAXSizeAttribute as CFString, v) == .success
    }

    @discardableResult
    func set(_ attr: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(ref, attr as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse)!) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(ref, action as CFString) == .success
    }

    func setTimeout(_ seconds: Float) { AXUIElementSetMessagingTimeout(ref, seconds) }
}

enum AXPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Ribbon to the Accessibility list.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
