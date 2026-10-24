// Draws the DMG window background (1x and 2x): swift make_dmg_background.swift <out-dir>
// Icon centres must match scripts/dmg_settings.py: app (165,185), Applications (495,185), guide (566,360).
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let W: CGFloat = 660, H: CGFloat = 440

let indigo = NSColor(srgbRed: 0.204, green: 0.259, blue: 0.627, alpha: 1)
let violet = NSColor(srgbRed: 0.471, green: 0.290, blue: 0.780, alpha: 1)
let rose = NSColor(srgbRed: 0.929, green: 0.408, blue: 0.565, alpha: 1)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: gc.cgContext, flipped: true)
    let ctx = gc.cgContext
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)   // top-left origin from here on
    let space = CGColorSpaceCreateDeviceRGB()

    // Soft background with brand-coloured glows in the corners.
    let bg = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 0.985, green: 0.98, blue: 1.0, alpha: 1).cgColor,
                                                      NSColor(srgbRed: 0.945, green: 0.935, blue: 0.99, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    func glow(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
        let g = CGGradient(colorsSpace: space, colors: [c.withAlphaComponent(a).cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    glow(violet, 40, 30, 260, 0.20)
    glow(rose, 640, 60, 240, 0.16)
    glow(indigo, 600, 430, 260, 0.12)

    @discardableResult
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color: NSColor = NSColor(white: 0.16, alpha: 1), width: CGFloat = 600, center: Bool = false) -> CGFloat {
        let p = NSMutableParagraphStyle()
        p.alignment = center ? .center : .left
        p.lineSpacing = 1.5
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        let str = NSAttributedString(string: s, attributes: attrs)
        let h = ceil(str.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height)
        str.draw(with: CGRect(x: x, y: y, width: width, height: h + 2), options: [.usesLineFragmentOrigin])
        return h
    }

    text("Install Ribbon", 0, 30, size: 28, weight: .bold, width: W, center: true)
    text("Drag the Ribbon icon onto the Applications folder.", 0, 68, size: 14, color: NSColor(white: 0.42, alpha: 1), width: W, center: true)

    // A gradient arrow from the app (165,185) to Applications (495,185).
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 250, y: 190))
    arrow.addQuadCurve(to: CGPoint(x: 398, y: 190), control: CGPoint(x: 324, y: 150))
    ctx.saveGState()
    ctx.addPath(arrow.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 4))
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 416, y: 196))
    head.addLine(to: CGPoint(x: 390, y: 176))
    head.addLine(to: CGPoint(x: 393, y: 204))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.clip()
    let ag = CGGradient(colorsSpace: space, colors: [indigo.cgColor, violet.cgColor, rose.cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(ag, start: CGPoint(x: 250, y: 0), end: CGPoint(x: 420, y: 0), options: [])
    ctx.restoreGState()

    // Steps card with a soft shadow.
    let card = CGRect(x: 24, y: 274, width: 450, height: 146)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: NSColor(srgbRed: 0.3, green: 0.2, blue: 0.5, alpha: 0.14).cgColor)
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setStrokeColor(NSColor(srgbRed: 0.47, green: 0.29, blue: 0.78, alpha: 0.12).cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()

    let steps = [
        "Drag Ribbon onto Applications.",
        "Open it from Applications. If macOS says it can't verify Ribbon: System Settings → Privacy & Security → Open Anyway.",
        "Take the two-minute tour, then press Tidy My Workspace and watch your windows fall into place.",
    ]
    var y: CGFloat = 290
    for (i, s) in steps.enumerated() {
        let dot = CGRect(x: 40, y: y - 1, width: 22, height: 22)
        ctx.saveGState()
        ctx.addEllipse(in: dot)
        ctx.clip()
        ctx.drawLinearGradient(ag, start: CGPoint(x: dot.minX, y: dot.minY), end: CGPoint(x: dot.maxX, y: dot.maxY), options: [])
        ctx.restoreGState()
        text("\(i + 1)", dot.minX, dot.minY + 3, size: 12, weight: .bold, color: .white, width: 22, center: true)
        let h = text(s, 74, y + 1, size: 12.5, color: NSColor(white: 0.2, alpha: 1), width: 384)
        y += max(22, h) + 10
    }

    text("Need a hand?", 496, 292, size: 12, weight: .semibold, color: NSColor(white: 0.35, alpha: 1), width: 140, center: true)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: outDir.appendingPathComponent("dmg-background.png"))
try! render(scale: 2).write(to: outDir.appendingPathComponent("dmg-background@2x.png"))
print("DMG background written")
