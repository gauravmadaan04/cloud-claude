import Foundation

public struct Modifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// Symbols in the order macOS menus use: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A shortcut, stored by physical key position so it works on any keyboard layout.
public struct KeyCombo: Codable, Hashable, CustomStringConvertible {
    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }

    /// Label for the key using a US layout; the app swaps in the user's layout when it can.
    public var description: String { modifiers.symbols + KeyCode.label(for: keyCode) }

    public func label(keyName: (UInt32) -> String?) -> String {
        modifiers.symbols + (keyName(keyCode) ?? KeyCode.label(for: keyCode))
    }
}

/// macOS virtual key codes (kVK_*).
public enum KeyCode {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03, h: UInt32 = 0x04
    public static let g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07, c: UInt32 = 0x08, v: UInt32 = 0x09
    public static let b: UInt32 = 0x0B, q: UInt32 = 0x0C, w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F
    public static let y: UInt32 = 0x10, t: UInt32 = 0x11, n1: UInt32 = 0x12, n2: UInt32 = 0x13, n3: UInt32 = 0x14
    public static let n4: UInt32 = 0x15, n6: UInt32 = 0x16, n5: UInt32 = 0x17, equal: UInt32 = 0x18, n9: UInt32 = 0x19
    public static let n7: UInt32 = 0x1A, minus: UInt32 = 0x1B, n8: UInt32 = 0x1C, n0: UInt32 = 0x1D
    public static let rightBracket: UInt32 = 0x1E, o: UInt32 = 0x1F, u: UInt32 = 0x20, leftBracket: UInt32 = 0x21
    public static let i: UInt32 = 0x22, p: UInt32 = 0x23, returnKey: UInt32 = 0x24, l: UInt32 = 0x25, j: UInt32 = 0x26
    public static let quote: UInt32 = 0x27, k: UInt32 = 0x28, semicolon: UInt32 = 0x29, backslash: UInt32 = 0x2A
    public static let comma: UInt32 = 0x2B, slash: UInt32 = 0x2C, n: UInt32 = 0x2D, m: UInt32 = 0x2E
    public static let period: UInt32 = 0x2F, tab: UInt32 = 0x30, space: UInt32 = 0x31, grave: UInt32 = 0x32
    public static let delete: UInt32 = 0x33, escape: UInt32 = 0x35
    public static let leftArrow: UInt32 = 0x7B, rightArrow: UInt32 = 0x7C, downArrow: UInt32 = 0x7D, upArrow: UInt32 = 0x7E
    public static let home: UInt32 = 0x73, end: UInt32 = 0x77, pageUp: UInt32 = 0x74, pageDown: UInt32 = 0x79
    public static let forwardDelete: UInt32 = 0x75

    static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "⇥", 0x31: "Space",
        0x32: "`", 0x33: "⌫", 0x35: "⎋", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘",
        0x74: "⇞", 0x79: "⇟", 0x75: "⌦",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    /// Keys whose label doesn't depend on the keyboard layout.
    public static func isLayoutIndependent(_ code: UInt32) -> Bool {
        [0x24, 0x30, 0x31, 0x33, 0x35, 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79, 0x75,
         0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F].contains(code)
    }

    public static func label(for code: UInt32) -> String { names[code] ?? "Key \(code)" }
}
