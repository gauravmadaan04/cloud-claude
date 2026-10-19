// Draws Ribbon's app icon at every size macOS needs: swift make_icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon grid: 824/1024 rounded square with a soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset * 1.15, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [NSColor(srgbRed: 0.20, green: 0.26, blue: 0.62, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.47, green: 0.29, blue: 0.78, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.93, green: 0.41, blue: 0.56, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Three columns on a strip that runs past the edges.
    let colH = body.height * 0.56
    let y = body.midY - colH / 2
    let gap = body.width * 0.045
    let widths: [CGFloat] = [0.30, 0.44, 0.30].map { $0 * body.width }
    var x = body.midX - widths[1] / 2 - gap - widths[0]
    for (i, w) in widths.enumerated() {
        let r = CGRect(x: x, y: y, width: w, height: colH)
        let p = CGPath(roundedRect: r, cornerWidth: body.width * 0.05, cornerHeight: body.width * 0.05, transform: nil)
        ctx.addPath(p)
        ctx.setFillColor(NSColor.white.withAlphaComponent(i == 1 ? 0.97 : 0.38).cgColor)
        ctx.fillPath()
        if i == 1 {
            // Title bar dots on the focused column.
            let d = body.width * 0.028
            for k in 0..<3 {
                let c = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen][k]
                ctx.setFillColor(c.cgColor)
                ctx.fillEllipse(in: CGRect(x: r.minX + d * 1.2 + CGFloat(k) * d * 1.6, y: r.maxY - d * 2.2, width: d, height: d))
            }
            ctx.setFillColor(NSColor(srgbRed: 0.47, green: 0.29, blue: 0.78, alpha: 0.25).cgColor)
            for k in 0..<3 {
                let lw = r.width * (k == 2 ? 0.45 : 0.7)
                ctx.fill(CGRect(x: r.minX + r.width * 0.14, y: r.midY + colH * 0.12 - CGFloat(k) * colH * 0.13, width: lw, height: colH * 0.055))
            }
        }
        x += w + gap
    }
    // Strip rail.
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    let railY = y - body.height * 0.09
    ctx.fill(CGRect(x: body.minX, y: railY, width: body.width, height: body.height * 0.012))
    ctx.setFillColor(NSColor.white.cgColor)
    let thumbW = widths[1] + gap
    let thumb = CGRect(x: body.midX - thumbW / 2, y: railY - body.height * 0.012, width: thumbW, height: body.height * 0.036)
    ctx.addPath(CGPath(roundedRect: thumb, cornerWidth: thumb.height / 2, cornerHeight: thumb.height / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("Icon written to \(out.path)")
