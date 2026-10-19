// Draws the DMG window background (1x and 2x): swift make_dmg_background.swift <out-dir>
// Icon centres must match scripts/dmg_settings.py.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let W: CGFloat = 660, H: CGFloat = 440

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

    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(srgbRed: 0.97, green: 0.96, blue: 1.0, alpha: 1).cgColor,
                                 NSColor(srgbRed: 0.93, green: 0.92, blue: 0.99, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: H), options: [])

    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color: NSColor = NSColor(white: 0.18, alpha: 1), width: CGFloat = 600, center: Bool = false) {
        let p = NSMutableParagraphStyle()
        p.alignment = center ? .center : .left
        p.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        NSAttributedString(string: s, attributes: attrs).draw(with: CGRect(x: x, y: y, width: width, height: 200),
                                                              options: [.usesLineFragmentOrigin])
    }

    text("Install Ribbon", 0, 26, size: 26, weight: .bold, width: W, center: true)
    text("Drag the Ribbon icon onto the Applications folder.", 0, 62, size: 14, color: NSColor(white: 0.4, alpha: 1), width: W, center: true)

    // Arrow from the app (165,185) to Applications (495,185).
    let accent = NSColor(srgbRed: 0.47, green: 0.29, blue: 0.78, alpha: 0.85)
    ctx.setStrokeColor(accent.cgColor)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 12])
    ctx.move(to: CGPoint(x: 245, y: 185)); ctx.addLine(to: CGPoint(x: 405, y: 185)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setFillColor(accent.cgColor)
    ctx.move(to: CGPoint(x: 428, y: 185)); ctx.addLine(to: CGPoint(x: 406, y: 172)); ctx.addLine(to: CGPoint(x: 406, y: 198)); ctx.closePath(); ctx.fillPath()

    // Steps card.
    let card = CGRect(x: 24, y: 278, width: 440, height: 140)
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.fillPath()
    let steps = [
        ("1", "Drag Ribbon onto Applications."),
        ("2", "Open Ribbon from Applications. If macOS says it couldn't verify it, go to System Settings → Privacy & Security and click Open Anyway."),
        ("3", "Follow the short welcome tour. It sets up permission and teaches the shortcuts."),
    ]
    var y: CGFloat = 292
    for (n, s) in steps {
        ctx.setFillColor(accent.cgColor)
        ctx.fillEllipse(in: CGRect(x: 38, y: y, width: 20, height: 20))
        text(n, 38, y + 2, size: 12, weight: .bold, color: .white, width: 20, center: true)
        text(s, 68, y + 1, size: 12.5, width: 380)
        y += s.count > 60 ? 48 : 32
    }
    text("Need help? Open", 486, 290, size: 12, color: NSColor(white: 0.45, alpha: 1), width: 160, center: true)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: outDir.appendingPathComponent("dmg-background.png"))
try! render(scale: 2).write(to: outDir.appendingPathComponent("dmg-background@2x.png"))
print("DMG background written")
