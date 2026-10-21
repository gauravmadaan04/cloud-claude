#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import HavenCore
import UniformTypeIdentifiers

/// The sample home folder for the product film: the usual sample files plus the clutter people really have
/// (scan0047.pdf, IMG_4021.HEIC, Document (3).pdf), the invoice Sam emailed last week and a recorded call.
extension FixtureFactory {
    static let filmMemo = "Notes from the planning call. The quarterly budget is approved, and the launch moves to Friday."

    static func makeFilm(at root: String) {
        make(at: root)
        let now = Date()
        func at(_ folder: String, _ name: String) -> String {
            let dir = (root as NSString).appendingPathComponent(folder)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return (dir as NSString).appendingPathComponent(name)
        }

        // The invoice: a scan with a meaningless name, attached to an email last week.
        let invoice = at("Downloads", "scan0047.pdf")
        invoicePDF(to: invoice)
        XAttr.setWhereFroms(["https://mail-attachment.googleusercontent.com/attachment/u/0/?ui=2&ik=film", "https://mail.google.com/"], path: invoice)
        mark(invoice, date: lastWeekMidpoint)

        // Look-alike clutter around it.
        let clutter: [(String, [String], Double)] = [
            ("scan0045.pdf", ["Lease Renewal", "Flat 4B, Linden Court", "Term: 12 months"], 26),
            ("scan0046.pdf", ["Electricity Bill", "September 2026", "Amount: 2,140"], 12),
            ("Document (3).pdf", ["Meeting Agenda", "1. Hiring", "2. Office move"], 3),
            ("download (7).pdf", ["Train Ticket", "Delhi to Jaipur", "Coach C2, Seat 41"], 33),
            ("final final v3.pdf", ["Pitch Deck", "Draft three", "Do not share"], 1),
        ]
        for (name, lines, days) in clutter {
            let p = at("Downloads", name)
            pdf(lines: lines, to: p)
            mark(p, date: now.addingTimeInterval(-days * day))
        }
        for (i, seed) in [21, 22, 23, 24].enumerated() {
            let p = at("Downloads", "IMG_402\(i + 1).HEIC")
            scene(seed: seed, size: CGSize(width: 1600, height: 1200), to: p, type: .heic)
            XAttr.setQuarantine(agent: "sharingd", path: p)
            mark(p, date: now.addingTimeInterval(-Double(i + 2) * day))
        }

        // A recorded call: found later by what was said in it.
        let memo = at("Music", "New Recording 14.m4a")
        speech(filmMemo, to: memo)
        mark(memo, date: now.addingTimeInterval(-3 * day))
    }

    /// A one-page invoice with a header band, a sender, a line item and a total.
    static func invoicePDF(to path: String) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(URL(fileURLWithPath: path) as CFURL, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor(srgbRed: 0.42, green: 0.30, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 700, width: 612, height: 92)).fill()
        func draw(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, white: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                        .foregroundColor: white ? NSColor.white : NSColor(white: 0.12, alpha: 1)]
            (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
        draw("INVOICE", 56, 730, 32, .bold, white: true)
        draw("No. 2291", 470, 738, 16, .medium, white: true)
        draw("Sam Patel Design Studio", 56, 640, 20, .semibold)
        draw("14 Hauz Khas Village, New Delhi", 56, 614, 13)
        draw("Billed to: Haven Labs", 56, 570, 13)
        draw("Date: 14 October 2026", 56, 550, 13)
        NSColor(white: 0.9, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 56, y: 498, width: 500, height: 1)).fill()
        draw("Logo and brand refresh", 56, 470, 15)
        draw("$1,240.00", 470, 470, 15, .medium)
        NSBezierPath(rect: NSRect(x: 56, y: 440, width: 500, height: 1)).fill()
        draw("Amount due", 56, 404, 15, .semibold)
        draw("$1,240.00", 452, 400, 20, .bold)
        draw("Please pay by 30 October. Thank you!", 56, 340, 13)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
#endif
