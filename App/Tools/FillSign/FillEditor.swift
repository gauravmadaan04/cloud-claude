import AppKit
import HavenCore
import PDFKit
import SwiftUI

/// What a click on the page does.
enum FillTool: Equatable {
    case select
    case text
    case detail(PersonalDetails.Field)
    case date
    case signature(UUID)
    case mark(FillMark)
    case whiteout
    case redact
    case markup(MarkupKind)

    var hint: String {
        switch self {
        case .select: return "Click anything you added to move it, drag its corner to resize it, or press Delete. Form fields can be typed in."
        case .text: return "Click where the text goes, then type."
        case .detail(let f): return "Click where your \(f.title.lowercased()) goes."
        case .date: return "Click where the date goes."
        case .signature: return "Click where it goes. Drag its corner to make it bigger or smaller."
        case .mark(let m): return "Click each box that needs a \(m.title.lowercased()). Press Escape when you're done."
        case .whiteout: return "Drag over what you want to cover with white."
        case .redact: return "Drag over what must be removed. Saved pages with redactions become pictures, so it's gone for good."
        case .markup(let k): return "Select words on the page to \(k.title.lowercased()) them."
        }
    }

    /// Tools you use many times in a row stay on; the rest go back to Select after one use.
    var staysOn: Bool {
        switch self {
        case .mark, .whiteout, .redact, .markup: return true
        default: return false
        }
    }
}

/// The open document, everything added to it, and Undo.
@MainActor
@Observable
final class FillEditor {
    let source: FileItem
    let document: PDFDocument
    var tool: FillTool = .select
    private(set) var items: [FillItem] = []
    var selectedID: UUID? { didSet { refreshSelection(old: oldValue) } }
    var lockForm = true
    var status: String?
    /// The copy has been handed to the save job.
    var saved = false
    /// Set when a new text item wants the keyboard.
    var focusText = 0
    let formFieldCount: Int
    @ObservationIgnored var onClose: (() -> Void)?

    @ObservationIgnored weak var view: PDFView?
    @ObservationIgnored private var annotations: [UUID: FillAnnotation] = [:]
    private var markups: [(page: Int, annotation: PDFAnnotation)] = []
    private var undoStack: [Snapshot] = []

    private struct Snapshot {
        var items: [FillItem]
        var markups: [(page: Int, annotation: PDFAnnotation)]
    }

    init?(source: FileItem) {
        guard let doc = PDFDocument(url: source.url), !doc.isLocked else { return nil }
        self.source = source
        document = doc
        var fields = 0
        for i in 0..<doc.pageCount {
            fields += doc.page(at: i)?.annotations.filter { $0.type == "Widget" }.count ?? 0
        }
        formFieldCount = fields
    }

    var selected: FillItem? { items.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var isEmpty: Bool { items.isEmpty && markups.isEmpty }

    // MARK: Adding

    func place(at point: CGPoint, on page: PDFPage) {
        let index = document.index(for: page)
        let rotation = page.rotation
        let prefs = Prefs.shared
        var item: FillItem
        switch tool {
        case .select, .markup:
            return
        case .text:
            item = textItem("", left: point, page: index, rotation: rotation)
        case .detail(let field):
            let value = prefs.personalDetails.value(field)
            guard !value.isEmpty else {
                status = "Add your \(field.title.lowercased()) in My Details first."
                return
            }
            item = textItem(value, left: point, page: index, rotation: rotation)
        case .date:
            item = textItem(prefs.dateStyle.string(from: Date()), left: point, page: index, rotation: rotation)
        case .signature(let id):
            guard let sig = SignatureLibrary.shared.all.first(where: { $0.id == id }) else { tool = .select; return }
            let width: CGFloat = sig.initials ? 54 : 150
            let aspect = CGFloat(sig.image.height) / CGFloat(max(1, sig.image.width))
            item = FillItem(page: index, center: point, size: CGSize(width: width, height: width * aspect),
                            content: .image(sig.image, initials: sig.initials))
        case .mark(let mark):
            item = FillItem(page: index, center: point, size: CGSize(width: 12, height: 12), content: .mark(mark), ink: prefs.fillInk)
        case .whiteout, .redact:
            item = FillItem(page: index, center: point, size: CGSize(width: 120, height: 16), content: tool == .redact ? .redaction : .whiteout)
        }
        if case .text = item.content { item.ink = prefs.fillInk }
        add(item)
        if !tool.staysOn {
            tool = .select
            selectedID = item.id
            if case .text("") = item.content { focusText += 1 }
        }
    }

    /// Text whose left edge is where you clicked.
    private func textItem(_ text: String, left point: CGPoint, page: Int, rotation: Int) -> FillItem {
        let fontSize = Prefs.shared.fillFontSize
        let size = FillDrawing.textSize(text.isEmpty ? "Type…" : text, fontSize: fontSize)
        let shift = FillDrawing.pageVector(CGVector(dx: size.width / 2, dy: 0), rotation: rotation)
        return FillItem(page: page, center: CGPoint(x: point.x + shift.dx, y: point.y + shift.dy), size: size,
                        content: .text(text), fontSize: fontSize)
    }

    /// A box drawn by dragging (white-out or redaction), from two corners in page coordinates.
    func addBox(from a: CGPoint, to b: CGPoint, on page: PDFPage) {
        let index = document.index(for: page)
        let turned = (page.rotation / 90) % 2 != 0
        let w = abs(a.x - b.x), h = abs(a.y - b.y)
        guard w > 3, h > 3 else { place(at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), on: page); return }
        let item = FillItem(page: index, center: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                            size: turned ? CGSize(width: h, height: w) : CGSize(width: w, height: h),
                            content: tool == .redact ? .redaction : .whiteout)
        add(item)
    }

    private func add(_ item: FillItem) {
        remember()
        items.append(item)
        attach(item)
        status = nil
    }

    func applyMarkup(_ kind: MarkupKind, to selection: PDFSelection) {
        let lines = selection.selectionsByLine()
        guard !lines.isEmpty else { return }
        remember()
        for line in lines {
            for page in line.pages {
                let b = line.bounds(for: page)
                guard b.width > 1, b.height > 1 else { continue }
                let a = PDFAnnotation(bounds: b, forType: kind.subtype, withProperties: nil)
                a.color = kind.color
                a.quadrilateralPoints = [NSValue(point: NSPoint(x: 0, y: b.height)), NSValue(point: NSPoint(x: b.width, y: b.height)),
                                         NSValue(point: NSPoint(x: 0, y: 0)), NSValue(point: NSPoint(x: b.width, y: 0))]
                page.addAnnotation(a)
                markups.append((document.index(for: page), a))
            }
        }
        view?.clearSelection()
    }

    // MARK: Changing

    func update(_ id: UUID, remember record: Bool = true, _ change: (inout FillItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if record { remember() }
        var item = items[i]
        change(&item)
        items[i] = item
        annotations[id]?.update(item)
        redraw(item.page)
    }

    /// New text for the selected item; its left edge stays put.
    func setText(_ text: String) {
        guard let item = selected, item.content.isText else { return }
        let rotation = document.page(at: item.page)?.rotation ?? 0
        update(item.id, remember: false) { it in
            let old = it.size
            it.content = .text(text)
            it.size = FillDrawing.textSize(text.isEmpty ? "Type…" : text, fontSize: it.fontSize)
            let shift = FillDrawing.pageVector(CGVector(dx: (it.size.width - old.width) / 2, dy: -(it.size.height - old.height) / 2), rotation: rotation)
            it.center = CGPoint(x: it.center.x + shift.dx, y: it.center.y + shift.dy)
        }
    }

    /// Bigger or smaller, keeping the top-left corner (as you see it) in place.
    func scale(_ id: UUID, by factor: CGFloat, remember record: Bool = true) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let rotation = document.page(at: item.page)?.rotation ?? 0
        update(id, remember: record) { it in
            let old = it.size
            if case .text(let t) = it.content {
                it.fontSize = min(72, max(6, it.fontSize * factor))
                it.size = FillDrawing.textSize(t.isEmpty ? "Type…" : t, fontSize: it.fontSize)
            } else {
                it.size = CGSize(width: max(6, old.width * factor), height: max(6, old.height * factor))
            }
            let shift = FillDrawing.pageVector(CGVector(dx: (it.size.width - old.width) / 2, dy: -(it.size.height - old.height) / 2), rotation: rotation)
            it.center = CGPoint(x: it.center.x + shift.dx, y: it.center.y + shift.dy)
        }
        // New text starts at the size you last chose.
        if item.content.isText, let now = items.first(where: { $0.id == id }) { Prefs.shared.fillFontSize = now.fontSize }
    }

    func setInk(_ ink: FillInk) {
        Prefs.shared.fillInk = ink
        guard let id = selectedID else { return }
        update(id) { $0.ink = ink }
    }

    func deleteSelected() {
        guard let id = selectedID, let i = items.firstIndex(where: { $0.id == id }) else { return }
        remember()
        let item = items.remove(at: i)
        detach(item.id, page: item.page)
        selectedID = nil
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let item = selected else { return }
        let rotation = document.page(at: item.page)?.rotation ?? 0
        let v = FillDrawing.pageVector(CGVector(dx: dx, dy: dy), rotation: rotation)
        update(item.id) { $0.center = CGPoint(x: $0.center.x + v.dx, y: $0.center.y + v.dy) }
    }

    // MARK: Forms

    /// Fills empty text fields whose names match your details. Returns how many it filled.
    @discardableResult
    func fillFormFromDetails() -> Int {
        let details = Prefs.shared.personalDetails
        guard !details.isEmpty else {
            status = "Add your details first (My Details), then try again."
            return 0
        }
        var filled = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for a in page.annotations where a.type == "Widget" && a.widgetFieldType == .text {
                guard (a.widgetStringValue ?? "").isEmpty, let name = a.fieldName,
                      let value = FormAutofill.value(forField: name, details: details, date: Date(), style: Prefs.shared.dateStyle) else { continue }
                a.widgetStringValue = value
                filled += 1
            }
            if filled > 0 { redraw(i) }
        }
        status = filled == 0 ? "No empty fields matched your details." : "Filled \(filled) field\(filled == 1 ? "" : "s") from My Details."
        return filled
    }

    // MARK: Undo

    private func remember() {
        undoStack.append(Snapshot(items: items, markups: markups))
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        for item in items { detach(item.id, page: item.page) }
        for m in markups where !last.markups.contains(where: { $0.annotation === m.annotation }) {
            document.page(at: m.page)?.removeAnnotation(m.annotation)
            redraw(m.page)
        }
        for m in last.markups where !markups.contains(where: { $0.annotation === m.annotation }) {
            document.page(at: m.page)?.addAnnotation(m.annotation)
            redraw(m.page)
        }
        markups = last.markups
        items = last.items
        for item in items { attach(item) }
        if let id = selectedID, !items.contains(where: { $0.id == id }) { selectedID = nil } else { refreshSelection(old: nil) }
    }

    // MARK: Hit testing (page coordinates)

    func item(at point: CGPoint, on page: PDFPage) -> FillItem? {
        let index = document.index(for: page)
        return items.last { $0.page == index && (annotations[$0.id]?.bounds.contains(point) ?? false) }
    }

    func bounds(of id: UUID) -> CGRect? { annotations[id]?.bounds }

    // MARK: Saving

    func save() {
        selectedID = nil
        // The job draws the items itself: write the document without the editor's previews.
        for item in items { detach(item.id, page: item.page) }
        let data = document.dataRepresentation()
        for item in items { attach(item) }
        guard let base = data else {
            status = "Couldn't read the document to save it."
            return
        }
        let plan = FillPlan(base: base, items: items.filter { if case .text(let t) = $0.content { return !t.isEmpty } else { return true } },
                            lockForm: lockForm)
        var extras = ToolExtras()
        extras.fill = plan
        saved = true
        ToolRunner.shared.start(.signPDF, [source], extras: extras)
        onClose?()
    }

    // MARK: Showing

    private func attach(_ item: FillItem) {
        guard let page = document.page(at: item.page) else { return }
        let a = FillAnnotation(item: item, rotation: page.rotation)
        a.isSelected = item.id == selectedID
        page.addAnnotation(a)
        annotations[item.id] = a
        redraw(item.page)
    }

    private func detach(_ id: UUID, page: Int) {
        if let a = annotations.removeValue(forKey: id) { document.page(at: page)?.removeAnnotation(a) }
        redraw(page)
    }

    private func refreshSelection(old: UUID?) {
        for (id, a) in annotations {
            let on = id == selectedID
            if a.isSelected != on {
                a.isSelected = on
                if let page = a.page { view?.annotationsChanged(on: page) }
            }
        }
    }

    private func redraw(_ index: Int) {
        guard let page = document.page(at: index) else { return }
        view?.annotationsChanged(on: page)
    }
}

/// The page view: placing, moving, resizing and deleting what's added; everything else (selecting text,
/// typing in form fields, links) works as usual.
final class FillPDFView: PDFView {
    weak var editor: FillEditor?

    private enum Drag {
        case move(id: UUID, start: CGPoint, center: CGPoint)
        case resize(id: UUID, startX: CGFloat, width: CGFloat)
        case box(page: PDFPage, start: CGPoint, current: CGPoint)
    }
    private var drag: Drag?
    private var boxView: NSView?

    override var acceptsFirstResponder: Bool { true }

    /// Edit › Undo (⌘Z) while the page has the keyboard takes back the last thing added, moved or deleted.
    @objc func undo(_ sender: Any?) { editor?.undo() }

    override func mouseDown(with event: NSEvent) {
        guard let editor else { return super.mouseDown(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        guard let page = page(for: p, nearest: false) else {
            editor.selectedID = nil
            return super.mouseDown(with: event)
        }
        let pp = convert(p, to: page)
        window?.makeFirstResponder(self)
        switch editor.tool {
        case .select:
            if let id = editor.selectedID, let b = editor.bounds(of: id) {
                let corner = convert(FillAnnotation.handleCorner(of: b.insetBy(dx: 2.5, dy: 2.5), rotation: page.rotation), from: page)
                if hypot(corner.x - p.x, corner.y - p.y) < 9 {
                    let vb = convert(b, from: page)
                    drag = .resize(id: id, startX: p.x, width: vb.width)
                    editor.update(id) { _ in }
                    return
                }
            }
            if let item = editor.item(at: pp, on: page) {
                editor.selectedID = item.id
                if event.clickCount == 2, item.content.isText { editor.focusText += 1; return }
                drag = .move(id: item.id, start: pp, center: item.center)
                editor.update(item.id) { _ in }
                return
            }
            editor.selectedID = nil
            super.mouseDown(with: event)
        case .markup:
            super.mouseDown(with: event)
        case .whiteout, .redact:
            drag = .box(page: page, start: pp, current: pp)
        default:
            editor.place(at: pp, on: page)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let editor, let d = drag else { return super.mouseDragged(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        switch d {
        case .move(let id, let start, let center):
            guard let item = editor.items.first(where: { $0.id == id }), let page = document?.page(at: item.page) else { return }
            let pp = convert(p, to: page)
            editor.update(id, remember: false) { $0.center = CGPoint(x: center.x + pp.x - start.x, y: center.y + pp.y - start.y) }
        case .resize(let id, let startX, let width):
            guard let item = editor.items.first(where: { $0.id == id }), let page = document?.page(at: item.page),
                  let b = editor.bounds(of: id) else { return }
            let target = max(8, width + (p.x - startX))
            let now = convert(b, from: page).width
            if now > 0 { editor.scale(id, by: target / now, remember: false) }
        case .box(let page, let start, _):
            let pp = convert(p, to: page)
            drag = .box(page: page, start: start, current: pp)
            showBox(convert(CGRect(x: min(start.x, pp.x), y: min(start.y, pp.y), width: abs(pp.x - start.x), height: abs(pp.y - start.y)), from: page),
                    black: editor.tool == .redact)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let editor else { return super.mouseUp(with: event) }
        defer { drag = nil }
        if case .box(let page, let start, let current) = drag {
            boxView?.removeFromSuperview()
            boxView = nil
            editor.addBox(from: start, to: current, on: page)
            return
        }
        if drag != nil { return }
        super.mouseUp(with: event)
        if case .markup(let kind) = editor.tool, let selection = currentSelection, !(selection.string ?? "").isEmpty {
            editor.applyMarkup(kind, to: selection)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let editor else { return super.keyDown(with: event) }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117 where editor.selectedID != nil: editor.deleteSelected()
        case 53: editor.tool = .select; editor.selectedID = nil
        case 123 where editor.selectedID != nil: editor.nudge(dx: -step, dy: 0)
        case 124 where editor.selectedID != nil: editor.nudge(dx: step, dy: 0)
        case 125 where editor.selectedID != nil: editor.nudge(dx: 0, dy: -step)
        case 126 where editor.selectedID != nil: editor.nudge(dx: 0, dy: step)
        default: super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let editor else { return }
        switch editor.tool {
        case .select, .markup: break
        default: NSCursor.crosshair.set()
        }
    }

    /// The box being dragged out, drawn over the page until the mouse is let go.
    private func showBox(_ r: CGRect, black: Bool) {
        let box = boxView ?? {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.borderWidth = 1
            v.layer?.borderColor = NSColor.systemPurple.cgColor
            addSubview(v)
            boxView = v
            return v
        }()
        box.layer?.backgroundColor = black ? NSColor.black.withAlphaComponent(0.6).cgColor : NSColor.white.withAlphaComponent(0.85).cgColor
        box.frame = r
    }
}

/// The page view, in SwiftUI.
struct FillDocumentView: NSViewRepresentable {
    let editor: FillEditor

    func makeNSView(context: Context) -> FillPDFView {
        let view = FillPDFView()
        view.document = editor.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor.underPageBackgroundColor
        view.editor = editor
        view.setAccessibilityIdentifier("fill.document")
        editor.view = view
        return view
    }

    func updateNSView(_ view: FillPDFView, context: Context) {}
}
