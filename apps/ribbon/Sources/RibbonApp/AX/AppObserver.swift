#if os(macOS)
import AppKit
import ApplicationServices

/// Receives Accessibility notifications from one running app.
final class AppObserver {
    enum Event {
        case windowCreated(AXElement)
        case focusChanged
        case moved(AXElement)
        case resized(AXElement)
        case minimized(AXElement)
        case deminimized(AXElement)
        case destroyed(AXElement)
        case titleChanged(AXElement)
        case appHidden
        case appShown
    }

    let pid: pid_t
    let app: AXElement
    let bundleID: String?
    let name: String
    private var observer: AXObserver?
    private var watchedWindows = Set<AXElement>()
    private let handler: (AppObserver, Event) -> Void

    static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    static let windowNotifications = [
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
    ]

    init(app running: NSRunningApplication, handler: @escaping (AppObserver, Event) -> Void) {
        pid = running.processIdentifier
        app = AXElement.app(pid)
        bundleID = running.bundleIdentifier
        name = running.localizedName ?? running.bundleIdentifier ?? "App"
        self.handler = handler
        app.setTimeout(1.0)
    }

    deinit { stop() }

    /// Returns false while the app isn't ready to talk to us yet (just launched); callers retry.
    @discardableResult
    func start() -> Bool {
        if observer != nil { return true }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &obs) == .success, let obs else { return false }
        let me = Unmanaged.passUnretained(self).toOpaque()
        var ok = false
        for n in AppObserver.appNotifications {
            let err = AXObserverAddNotification(obs, app.ref, n as CFString, me)
            if err == .success || err == .notificationAlreadyRegistered { ok = true }
        }
        guard ok else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        return true
    }

    func stop() {
        guard let obs = observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = nil
        watchedWindows.removeAll()
    }

    func watch(_ window: AXElement) {
        guard let obs = observer, !watchedWindows.contains(window) else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in AppObserver.windowNotifications {
            AXObserverAddNotification(obs, window.ref, n as CFString, me)
        }
        window.setTimeout(0.6)
        watchedWindows.insert(window)
    }

    func unwatch(_ window: AXElement) {
        guard let obs = observer, watchedWindows.remove(window) != nil else { return }
        for n in AppObserver.windowNotifications {
            AXObserverRemoveNotification(obs, window.ref, n as CFString)
        }
    }

    fileprivate func receive(_ element: AXUIElement, _ name: String) {
        let el = AXElement(element)
        switch name {
        case kAXWindowCreatedNotification: handler(self, .windowCreated(el))
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification: handler(self, .focusChanged)
        case kAXWindowMovedNotification: handler(self, .moved(el))
        case kAXWindowResizedNotification: handler(self, .resized(el))
        case kAXWindowMiniaturizedNotification: handler(self, .minimized(el))
        case kAXWindowDeminiaturizedNotification: handler(self, .deminimized(el))
        case kAXUIElementDestroyedNotification:
            watchedWindows.remove(el)
            handler(self, .destroyed(el))
        case kAXTitleChangedNotification: handler(self, .titleChanged(el))
        case kAXApplicationHiddenNotification: handler(self, .appHidden)
        case kAXApplicationShownNotification: handler(self, .appShown)
        default: break
        }
    }
}

private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let me = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
    me.receive(element, notification as String)
}
#endif
