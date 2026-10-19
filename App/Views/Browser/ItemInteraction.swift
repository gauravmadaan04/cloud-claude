import AppKit
import HavenCore
import SwiftUI

/// An invisible AppKit layer over a file card or row that gives Finder-like behaviour:
/// click / ⌘-click / ⇧-click selection, double-click, right-click menu, hover, and dragging
/// one or many files out to other apps.
struct ItemInteraction: NSViewRepresentable {
    var onMouseDown: (NSEvent.ModifierFlags, Int) -> Void
    var onMouseUp: (NSEvent.ModifierFlags, Bool) -> Void = { _, _ in }
    var onHover: (Bool) -> Void = { _ in }
    var dragURLs: () -> [URL]
    var menu: () -> NSMenu?
    var accessibilityLabel: String = ""

    /// The same interaction reporting hover to the card that shows it.
    func reportingHover(_ handler: @escaping (Bool) -> Void) -> ItemInteraction {
        var copy = self
        copy.onHover = handler
        return copy
    }

    func makeNSView(context: Context) -> InteractionView {
        let v = InteractionView()
        v.config = self
        return v
    }

    func updateNSView(_ v: InteractionView, context: Context) {
        v.config = self
        v.setAccessibilityLabel(accessibilityLabel)
    }
}

final class InteractionView: NSView, NSDraggingSource {
    var config: ItemInteraction?
    private var downEvent: NSEvent?
    private var dragged = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { config?.onHover(true) }
    override func mouseExited(with event: NSEvent) { config?.onHover(false) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            config?.onMouseDown(event.modifierFlags, 1)
            if let menu = config?.menu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
            return
        }
        downEvent = event
        dragged = false
        config?.onMouseDown(event.modifierFlags, event.clickCount)
    }

    override func mouseUp(with event: NSEvent) {
        config?.onMouseUp(event.modifierFlags, dragged)
        downEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, !dragged else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 16 else { return }
        dragged = true
        guard let urls = config?.dragURLs(), !urls.isEmpty else { return }
        let origin = convert(down.locationInWindow, from: nil)
        let items: [NSDraggingItem] = urls.prefix(60).enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let side: CGFloat = 56
            let offset = CGFloat(min(index, 6)) * 5
            item.setDraggingFrame(NSRect(x: origin.x - side / 2 + offset, y: origin.y - side / 2 - offset, width: side, height: side), contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic, .link] : []
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        config?.onMouseDown(event.modifierFlags.union(.control), 1)
        return config?.menu()
    }

    override func isAccessibilityElement() -> Bool { false }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = .command, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        self.target = self
        self.keyEquivalentModifierMask = modifiers
        if let symbol { self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// The right-click menu for one or more files.
@MainActor
enum ItemMenu {
    static func make(for items: [FileItem]) -> NSMenu {
        let model = AppModel.shared
        let menu = NSMenu()
        guard let first = items.first else { return menu }
        let single = items.count == 1

        menu.addItem(ClosureMenuItem(single && first.kind == .folder ? "Open in Haven" : "Open", symbol: "arrow.up.forward.app") {
            model.open(items)
        })
        if single, first.kind != .folder {
            let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWith.image = NSImage(systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: nil)
            let sub = NSMenu()
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: first.url).prefix(12)
            for appURL in apps {
                let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
                let item = ClosureMenuItem(name) {
                    NSWorkspace.shared.open([first.url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                }
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                sub.addItem(item)
            }
            if !apps.isEmpty {
                openWith.submenu = sub
                menu.addItem(openWith)
            }
        }
        if first.kind != .folder {
            menu.addItem(ClosureMenuItem("Quick Look", symbol: "eye") {
                model.selectedIDs = Set(items.map(\.id))
                model.quickLookURL = first.url
            })
        }
        menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") { model.revealInFinder(items) })
        if single, model.selection != .folder(first.parentPath) || model.isSearching {
            menu.addItem(ClosureMenuItem("Show in Enclosing Folder", symbol: "arrow.turn.left.up") { model.showInHaven(first) })
        }
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(single ? "Copy “\(first.name)”" : "Copy \(items.count) Items", symbol: "doc.on.doc") {
            model.copyFiles(items)
        })
        menu.addItem(ClosureMenuItem("Copy Path", symbol: "link", key: "c", modifiers: [.command, .option]) { model.copyPaths(items) })
        if items.contains(where: { $0.kind.hasReadableText }) {
            menu.addItem(ClosureMenuItem("Copy Text", symbol: "text.quote", key: "c", modifiers: [.command, .shift]) { model.copyText(items) })
        }
        let share = NSSharingServicePicker(items: items.map(\.url)).standardShareMenuItem
        menu.addItem(share)
        menu.addItem(.separator())

        if single, first.kind == .folder {
            let pinned = Prefs.shared.pinnedFolders.contains(first.path)
            menu.addItem(ClosureMenuItem(pinned ? "Unpin from Sidebar" : "Pin to Sidebar", symbol: pinned ? "pin.slash" : "pin") {
                model.togglePin(first.path)
            })
        } else if single {
            let folder = first.parentPath
            let pinned = Prefs.shared.pinnedFolders.contains(folder)
            if !pinned {
                menu.addItem(ClosureMenuItem("Pin “\(first.parentName)” to Sidebar", symbol: "pin") { model.togglePin(folder) })
            }
        }
        menu.addItem(ClosureMenuItem("Get Info", symbol: "info.circle", key: "i") {
            model.selectedIDs = Set(items.map(\.id))
            model.showInspector = true
        })
        menu.addItem(.separator())
        let trash = ClosureMenuItem("Move to Trash", symbol: "trash", key: "\u{8}") {
            model.trash(items, reason: "Moved by you", undoManager: NSApp.keyWindow?.undoManager)
        }
        menu.addItem(trash)
        return menu
    }
}
