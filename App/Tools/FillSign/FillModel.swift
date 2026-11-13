import AppKit
import CoreText
import HavenCore
import PDFKit

/// A tick, a cross or a dot, for boxes on forms that aren't fillable.
enum FillMark: String, CaseIterable, Identifiable {
    case check, cross, dot

    var id: String { rawValue }
    var title: String {
        switch self {
        case .check: return "Tick"
        case .cross: return "Cross"
        case .dot: return "Dot"
        }
    }
    var symbol: String {
        switch self {
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .dot: return "circle.fill"
        }
    }
}

/// The colour of text and marks: black, or the blue many forms ask for.
enum FillInk: String, CaseIterable, Identifiable {
    case black, blue

    var id: String { rawValue }
    var title: String { self == .black ? "Black" : "Blue" }
    var cgColor: CGColor {
        self == .black ? CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1) : CGColor(red: 0.05, green: 0.16, blue: 0.55, alpha: 1)
    }
}

/// Highlighting, underlining or striking out words that are already on the page.
enum MarkupKind: String, CaseIterable, Identifiable {
    case highlight, underline, strikeOut

    var id: String { rawValue }
    var title: String {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikeOut: return "Strike Through"
        }
    }
    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikeOut: return "strikethrough"
        }
    }
    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }
    var color: NSColor {
        switch self {
        case .highlight: return NSColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 0.45)
        case .underline: return NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1)
        case .strikeOut: return NSColor(srgbRed: 0.85, green: 0.12, blue: 0.12, alpha: 1)
        }
    }
}

/// What something added to a page is.
enum FillContent {
    /// Typed text, one of your details or a date.
    case text(String)
    /// A signature or initials.
    case image(CGImage, initials: Bool)
    case mark(FillMark)
    /// A white box over something on the page.
    case whiteout
    /// A black box; on saving, the page becomes a picture so what's underneath is gone for good.
    case redaction

    var isText: Bool { if case .text = self { return true } else { return false } }
    var isSignature: Bool { if case .image = self { return true } else { return false } }
    var isRedaction: Bool { if case .redaction = self { return true } else { return false } }
    var isBox: Bool {
        switch self {
        case .whiteout, .redaction: return true
        default: return false
        }
    }
}

/// One thing added to a page. `center` is in the page's own coordinates; `size` is how big it looks, upright, on screen.
struct FillItem: Identifiable {
    var id = UUID()
    var page: Int
    var center: CGPoint
    var size: CGSize
    var content: FillContent
    var fontSize: CGFloat = 13
    var ink: FillInk = .black
}

/// What Fill & Sign hands to the job that writes the new PDF: the document with its form answers and highlights,
/// and everything to draw onto its pages.
struct FillPlan {
    var base: Data
    var items: [FillItem]
    /// Turn form fields into plain page content, so the answers can't be changed.
    var lockForm: Bool

    var hasSignature: Bool { items.contains { $0.content.isSignature } }
}

/// Draws what Fill & Sign adds, the same way in the editor and in the saved file.
enum FillDrawing {
    static let padding: CGFloat = 2
    static let lineSpacing: CGFloat = 1.22

    static func font(_ size: CGFloat) -> CTFont { CTFontCreateWithName("Helvetica" as CFString, size, nil) }

    /// How much room text takes, upright.
    static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let lines = text.isEmpty ? [" "] : text.components(separatedBy: "\n")
        let f = font(fontSize)
        var width: CGFloat = 0
        for line in lines {
            let ct = CTLineCreateWithAttributedString(attributed(line, f, ink: .black))
            width = max(width, CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil)))
        }
        let height = CGFloat(lines.count) * fontSize * lineSpacing
        return CGSize(width: ceil(width) + padding * 2, height: ceil(height) + padding * 2)
    }

    static func attributed(_ s: String, _ f: CTFont, ink: FillInk) -> CFAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cgColor,
        ]
        return NSAttributedString(string: s, attributes: attrs) as CFAttributedString
    }

    /// The item's box in page coordinates: a page shown turned a quarter has its width and height swapped.
    static func pageBounds(center: CGPoint, size: CGSize, rotation: Int) -> CGRect {
        let turned = (rotation / 90) % 2 != 0
        let w = turned ? size.height : size.width, h = turned ? size.width : size.height
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    /// A step in the upright (on-screen) direction, as a step in page coordinates.
    static func pageVector(_ v: CGVector, rotation: Int) -> CGVector {
        let a = CGFloat(rotation) * .pi / 180
        return CGVector(dx: v.dx * cos(a) - v.dy * sin(a), dy: v.dx * sin(a) + v.dy * cos(a))
    }

    /// Draws an item in page coordinates, turned to read upright on a page shown at `rotation` degrees.
    static func draw(_ item: FillItem, rotation: Int, in ctx: CGContext, placeholder: Bool = false) {
        ctx.saveGState()
        ctx.translateBy(x: item.center.x, y: item.center.y)
        ctx.rotate(by: CGFloat(rotation) * .pi / 180)
        let r = CGRect(x: -item.size.width / 2, y: -item.size.height / 2, width: item.size.width, height: item.size.height)
        switch item.content {
        case .text(let text):
            if text.isEmpty {
                if placeholder { drawPlaceholder(in: r, ctx: ctx, fontSize: item.fontSize) }
            } else {
                drawText(text, in: r, fontSize: item.fontSize, ink: item.ink, ctx: ctx)
            }
        case .image(let image, _):
            ctx.interpolationQuality = .high
            ctx.draw(image, in: r)
        case .mark(let mark):
            drawMark(mark, in: r, ink: item.ink, ctx: ctx)
        case .whiteout:
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(r)
        case .redaction:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(r)
        }
        ctx.restoreGState()
    }

    private static func drawText(_ text: String, in r: CGRect, fontSize: CGFloat, ink: FillInk, ctx: CGContext) {
        let f = font(fontSize)
        let lines = text.components(separatedBy: "\n")
        let lineHeight = fontSize * lineSpacing
        ctx.textMatrix = .identity
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let ct = CTLineCreateWithAttributedString(attributed(line, f, ink: ink))
            // First line at the top; baselines step down.
            let baseline = r.maxY - padding - CGFloat(i + 1) * lineHeight + (lineHeight - fontSize) / 2 + CTFontGetDescent(f)
            ctx.textPosition = CGPoint(x: r.minX + padding, y: baseline)
            CTLineDraw(ct, ctx)
        }
    }

    private static func drawPlaceholder(in r: CGRect, ctx: CGContext, fontSize: CGFloat) {
        ctx.setStrokeColor(CGColor(red: 0.4, green: 0.3, blue: 0.95, alpha: 0.8))
        ctx.setLineWidth(0.8)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.stroke(r)
        ctx.setLineDash(phase: 0, lengths: [])
        let f = font(fontSize)
        let ct = CTLineCreateWithAttributedString(NSAttributedString(string: "Type…", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.5, alpha: 1),
        ]) as CFAttributedString)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: r.minX + padding, y: r.minY + padding + CTFontGetDescent(f))
        CTLineDraw(ct, ctx)
    }

    private static func drawMark(_ mark: FillMark, in r: CGRect, ink: FillInk, ctx: CGContext) {
        let s = min(r.width, r.height)
        let box = CGRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setFillColor(ink.cgColor)
        ctx.setLineWidth(max(1, s * 0.13))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch mark {
        case .check:
            ctx.move(to: CGPoint(x: box.minX + s * 0.12, y: box.minY + s * 0.5))
            ctx.addLine(to: CGPoint(x: box.minX + s * 0.4, y: box.minY + s * 0.18))
            ctx.addLine(to: CGPoint(x: box.maxX - s * 0.08, y: box.maxY - s * 0.12))
            ctx.strokePath()
        case .cross:
            let i = s * 0.16
            ctx.move(to: CGPoint(x: box.minX + i, y: box.minY + i))
            ctx.addLine(to: CGPoint(x: box.maxX - i, y: box.maxY - i))
            ctx.move(to: CGPoint(x: box.minX + i, y: box.maxY - i))
            ctx.addLine(to: CGPoint(x: box.maxX - i, y: box.minY + i))
            ctx.strokePath()
        case .dot:
            ctx.fillEllipse(in: box.insetBy(dx: s * 0.22, dy: s * 0.22))
        }
    }
}

/// How an item shows in the editor: drawn the way it will be saved, with a frame and a size handle when selected.
/// The annotation is a little bigger than the item, so the frame and handle are redrawn (and erased) with it.
final class FillAnnotation: PDFAnnotation {
    static let margin: CGFloat = 5
    var item: FillItem
    var rotation: Int
    var isSelected = false

    init(item: FillItem, rotation: Int) {
        self.item = item
        self.rotation = rotation
        super.init(bounds: Self.area(item, rotation), forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { nil }

    static func area(_ item: FillItem, _ rotation: Int) -> CGRect {
        FillDrawing.pageBounds(center: item.center, size: item.size, rotation: rotation).insetBy(dx: -margin, dy: -margin)
    }

    func update(_ new: FillItem) {
        item = new
        bounds = Self.area(new, rotation)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        FillDrawing.draw(item, rotation: rotation, in: context, placeholder: true)
        guard isSelected else { return }
        context.saveGState()
        let frame = bounds.insetBy(dx: 2.5, dy: 2.5)
        context.setStrokeColor(CGColor(red: 0.42, green: 0.3, blue: 0.95, alpha: 1))
        context.setLineWidth(1)
        context.stroke(frame)
        // The size handle sits at the bottom-right corner as you see it.
        let corner = FillAnnotation.handleCorner(of: frame, rotation: rotation)
        let handle = CGRect(x: corner.x - 2.5, y: corner.y - 2.5, width: 5, height: 5)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(handle)
        context.stroke(handle)
        context.restoreGState()
    }

    /// The page point that shows as the bottom-right corner on screen.
    static func handleCorner(of r: CGRect, rotation: Int) -> CGPoint {
        switch ((rotation % 360) + 360) % 360 {
        case 90: return CGPoint(x: r.maxX, y: r.maxY)
        case 180: return CGPoint(x: r.minX, y: r.maxY)
        case 270: return CGPoint(x: r.minX, y: r.minY)
        default: return CGPoint(x: r.maxX, y: r.minY)
        }
    }
}
