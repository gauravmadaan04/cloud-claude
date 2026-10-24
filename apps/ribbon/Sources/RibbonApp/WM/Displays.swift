#if os(macOS)
import AppKit
import RibbonCore

/// One connected display, in Accessibility (top-left origin) coordinates.
struct Display: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: Rect
    let visible: Rect
    let isMain: Bool
}

enum Displays {
    static func current() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(num.uint32Value)
            let uuid: String
            if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(nil, u) as String
            } else {
                uuid = "display-\(id)"
            }
            return Display(id: id, uuid: uuid, name: screen.localizedName, frame: toAX(screen.frame),
                           visible: toAX(screen.visibleFrame), isMain: CGDisplayIsMain(id) != 0)
        }
    }

    /// Height of the display with the menu bar; AppKit and AX coordinates flip around it.
    static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }

    static func toAX(_ r: NSRect) -> Rect {
        Rect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, w: r.width, h: r.height)
    }

    static func toNS(_ r: Rect) -> NSRect {
        NSRect(x: r.x, y: primaryHeight - r.y - r.h, width: r.w, height: r.h)
    }

    static func toAX(point p: NSPoint) -> Point { Point(x: p.x, y: primaryHeight - p.y) }

    static var mouseLocation: Point { toAX(point: NSEvent.mouseLocation) }
}

/// Read-only access to macOS Spaces through the private SkyLight calls that yabai, Amethyst and
/// Hammerspoon use. Everything degrades to "one Space" if a symbol is missing.
enum Spaces {
    typealias ConnectionID = Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ names: String...) -> T? {
        for n in names {
            if let h = handle, let p = dlsym(h, n) { return unsafeBitCast(p, to: T.self) }
            if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), n) { return unsafeBitCast(p, to: T.self) }
        }
        return nil
    }

    private typealias MainConnectionFn = @convention(c) () -> ConnectionID
    private typealias CopyDisplaySpacesFn = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let mainConnection: MainConnectionFn? = sym("SLSMainConnectionID", "CGSMainConnectionID")
    private static let copyDisplaySpaces: CopyDisplaySpacesFn? = sym("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces")
    private static let copySpacesForWindows: CopySpacesForWindowsFn? = sym("SLSCopySpacesForWindows", "CGSCopySpacesForWindows")

    private static let cid: ConnectionID = mainConnection?() ?? 0

    struct DisplaySpaces {
        var current: UInt64
        var all: [UInt64]
        var currentIsFullscreen: Bool
    }

    /// Current and ordered Spaces keyed by display UUID ("Main" when displays share Spaces).
    static func snapshot() -> [String: DisplaySpaces] {
        guard let fn = copyDisplaySpaces, let arr = fn(cid)?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        var out: [String: DisplaySpaces] = [:]
        for d in arr {
            guard let ident = d["Display Identifier"] as? String else { continue }
            let cur = d["Current Space"] as? [String: Any]
            let curID = (cur?["id64"] as? NSNumber)?.uint64Value ?? (cur?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0
            let type = (cur?["type"] as? NSNumber)?.intValue ?? 0
            let all = (d["Spaces"] as? [[String: Any]] ?? []).compactMap {
                ($0["id64"] as? NSNumber)?.uint64Value ?? ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value
            }
            out[ident] = DisplaySpaces(current: curID, all: all, currentIsFullscreen: type == 4)
        }
        return out
    }

    static func spaces(for snapshot: [String: DisplaySpaces], displayUUID: String) -> DisplaySpaces? {
        snapshot[displayUUID] ?? snapshot["Main"] ?? snapshot.values.first
    }

    /// The Spaces a window is on (empty if unknown).
    static func spaces(ofWindow wid: CGWindowID) -> [UInt64] {
        guard let fn = copySpacesForWindows else { return [] }
        let arr = [NSNumber(value: wid)] as CFArray
        guard let res = fn(cid, 0x7, arr)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return res.map { $0.uint64Value }
    }
}

/// Facts from the window server that don't need Accessibility (and work across Spaces).
enum WindowServer {
    struct Info {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: Rect
        let onScreen: Bool
    }

    /// The frontmost ordinary window under a point that isn't one of Ribbon's own.
    static func topWindow(at p: Point) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let me = getpid()
        for d in list {
            guard (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != me,
                  let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let b = d[kCGWindowBounds as String], let r = CGRect(dictionaryRepresentation: b as! CFDictionary) else { continue }
            if Rect(x: r.origin.x, y: r.origin.y, w: r.width, h: r.height).contains(p) { return id }
        }
        return nil
    }

    static func all(onScreenOnly: Bool = false) -> [CGWindowID: Info] {
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var out: [CGWindowID: Info] = [:]
        for d in list {
            guard let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            var r = CGRect.zero
            if let b = d[kCGWindowBounds as String], let rr = CGRect(dictionaryRepresentation: b as! CFDictionary) { r = rr }
            let on = (d[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            out[id] = Info(id: id, pid: pid, layer: layer,
                           bounds: Rect(x: r.origin.x, y: r.origin.y, w: r.width, h: r.height), onScreen: on)
        }
        return out
    }
}
#endif
