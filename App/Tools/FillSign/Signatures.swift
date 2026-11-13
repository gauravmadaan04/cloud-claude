import AppKit
import CoreText
import HavenCore
import SwiftUI
import UniformTypeIdentifiers

/// A signature or initials kept on this Mac.
struct SavedSignature: Identifiable {
    let id: UUID
    let initials: Bool
    let image: CGImage
    let url: URL
}

/// Your signatures and initials, as see-through pictures in Haven's support folder.
@MainActor
@Observable
final class SignatureLibrary {
    static let shared = SignatureLibrary()
    private(set) var all: [SavedSignature] = []

    var signatures: [SavedSignature] { all.filter { !$0.initials } }
    var initialsList: [SavedSignature] { all.filter(\.initials) }

    nonisolated static var folder: URL {
        LaunchOptions.current.supportDirectory.appendingPathComponent("Signatures", isDirectory: true)
    }

    private init() {
        migrate()
        reload()
    }

    /// The one signature earlier versions kept becomes the first saved signature.
    private func migrate() {
        let old = LaunchOptions.current.supportDirectory.appendingPathComponent("signature.png")
        guard FileManager.default.fileExists(atPath: old.path) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: old, to: Self.folder.appendingPathComponent("signature-\(UUID().uuidString).png"))
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        all = urls.filter { $0.pathExtension == "png" }.compactMap { url -> (SavedSignature, Date)? in
            let name = url.deletingPathExtension().lastPathComponent
            let initials = name.hasPrefix("initials-")
            guard name.hasPrefix("signature-") || initials,
                  let id = UUID(uuidString: String(name.drop(while: { $0 != "-" }).dropFirst())),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let made = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (SavedSignature(id: id, initials: initials, image: image, url: url), made)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    @discardableResult
    func add(_ image: CGImage, initials: Bool) -> SavedSignature? {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let id = UUID()
        let url = Self.folder.appendingPathComponent("\(initials ? "initials" : "signature")-\(id.uuidString).png")
        do { try ImageTools.write(image, as: .png, to: url, props: [:]) } catch { return nil }
        reload()
        return all.first { $0.id == id }
    }

    func remove(_ signature: SavedSignature) {
        try? FileManager.default.removeItem(at: signature.url)
        reload()
    }
}

/// Makes signature pictures: drawn, typed in a handwriting font, or cut out of a photo of one on paper.
enum SignatureMaker {
    static let ink = CGColor(red: 0.05, green: 0.1, blue: 0.45, alpha: 1)

    struct Hand: Identifiable, Hashable {
        let name: String
        let postScript: String
        var id: String { postScript }
    }

    /// Handwriting fonts that come with macOS, the ones this Mac has.
    static let hands: [Hand] = [
        Hand(name: "Snell Roundhand", postScript: "SnellRoundhand"),
        Hand(name: "Savoye", postScript: "SavoyeLetPlain"),
        Hand(name: "Bradley Hand", postScript: "BradleyHandITCTT-Bold"),
        Hand(name: "Apple Chancery", postScript: "Apple-Chancery"),
        Hand(name: "Noteworthy", postScript: "Noteworthy-Light"),
    ].filter { NSFont(name: $0.postScript, size: 12) != nil }

    /// Typed text as a see-through picture, cropped to the ink.
    static func typed(_ text: String, hand: Hand, size: CGFloat = 64) -> CGImage? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        let font = CTFontCreateWithName(hand.postScript as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: attrs) as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // Script fonts swing well outside their box: leave plenty of room, then crop.
        let pad = size * 0.8, scale: CGFloat = 2
        let w = Int((width + pad * 2) * scale), h = Int((ascent + descent + pad * 2) * scale)
        guard let ctx = bitmap(w, h) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: pad, y: pad + descent)
        CTLineDraw(line, ctx)
        return ctx.makeImage().flatMap { cropToInk($0) }
    }

    /// A photo of a signature on light paper: the paper becomes see-through, the ink stays.
    static func fromPhoto(_ url: URL) -> CGImage? {
        guard let s = try? ImageTools.source(url), let photo = try? ImageTools.upright(s.0, props: s.1, maxSide: 1600) else { return nil }
        let w = photo.width, h = photo.height
        guard let ctx = bitmap(w, h) else { return nil }
        ctx.draw(photo, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return nil }
        let px = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func lum(_ i: Int) -> Double { (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255 }
        // How light the paper is: the brighter part of the picture.
        var samples: [Double] = []
        for i in stride(from: 0, to: w * h, by: 37) { samples.append(lum(i * 4)) }
        samples.sort()
        let paper = samples.isEmpty ? 0.9 : samples[samples.count * 3 / 4]
        let cutoff = max(0.25, paper - 0.16)
        for i in 0..<(w * h) {
            let p = i * 4
            let l = lum(p)
            let alpha = l >= cutoff ? 0 : min(1, (cutoff - l) / 0.22)
            // Premultiplied: colour scales with how solid the ink is.
            px[p] = UInt8(Double(px[p]) * alpha)
            px[p + 1] = UInt8(Double(px[p + 1]) * alpha)
            px[p + 2] = UInt8(Double(px[p + 2]) * alpha)
            px[p + 3] = UInt8(alpha * 255)
        }
        return ctx.makeImage().flatMap { cropToInk($0) }
    }

    /// The picture trimmed to where the ink is, with a little room around it.
    static func cropToInk(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = bitmap(w, h) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return nil }
        let px = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 8
        let r = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                       width: min(w, maxX + pad + 1) - max(0, minX - pad), height: min(h, maxY + pad + 1) - max(0, minY - pad))
        return ctx.makeImage()?.cropping(to: r)
    }

    private static func bitmap(_ w: Int, _ h: Int) -> CGContext? {
        guard w > 0, h > 0 else { return nil }
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

/// A pad you sign on: every drag is a stroke.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @State private var inStroke = false

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes { context.stroke(Self.path(stroke), with: .color(.init(red: 0.05, green: 0.1, blue: 0.45)), lineWidth: 3.2) }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if inStroke, !strokes.isEmpty {
                    strokes[strokes.count - 1].append(value.location)
                } else {
                    strokes.append([value.location])
                    inStroke = true
                }
            }
            .onEnded { _ in inStroke = false })
    }

    static func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }

    /// The strokes as a see-through picture, cropped to the ink, at twice the size for crisp printing.
    static func render(_ strokes: [[CGPoint]]) -> CGImage? {
        let all = strokes.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return nil }
        let pad: CGFloat = 8, scale: CGFloat = 2
        let w = Int((maxX - minX + pad * 2) * scale), h = Int((maxY - minY + pad * 2) * scale)
        guard w > 4, h > 4, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Canvas points run top to bottom; bitmaps bottom to top.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -minX + pad, y: -minY + pad)
        ctx.setStrokeColor(SignatureMaker.ink)
        ctx.setLineWidth(3.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 1 {
            ctx.move(to: stroke[0])
            for pt in stroke.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}

/// Making a new signature or initials: draw it, type it, or use a photo.
struct SignatureMakerSheet: View {
    let initials: Bool
    var onDone: (SavedSignature?) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case type = "Type", draw = "Draw", photo = "Photo"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .type
    @State private var strokes: [[CGPoint]] = []
    @State private var typed = ""
    @State private var hand = SignatureMaker.hands.first
    @State private var photo: CGImage?
    @State private var photoProblem: String?
    @Environment(\.theme) private var theme

    private var noun: String { initials ? "initials" : "signature" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: initials ? "textformat" : "signature")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(initials ? "New Initials" : "New Signature").font(.system(size: 19, weight: .bold, design: theme.headingDesign))
                    Text("Kept on this Mac, ready for every form.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Picker("How", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("signmaker.mode")

            switch mode {
            case .type: typePane
            case .draw: drawPane
            case .photo: photoPane
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button("Save \(initials ? "Initials" : "Signature")") {
                    guard let image = made else { return }
                    onDone(SignatureLibrary.shared.add(image, initials: initials))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(made == nil)
                .accessibilityIdentifier("signmaker.save")
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            let d = Prefs.shared.personalDetails
            typed = initials ? d.effectiveInitials : d.name
        }
    }

    private var made: CGImage? {
        switch mode {
        case .type: return hand.flatMap { SignatureMaker.typed(typed, hand: $0) }
        case .draw: return SignaturePad.render(strokes)
        case .photo: return photo
        }
    }

    private var typePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(initials ? "Your initials" : "Your name", text: $typed)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("signmaker.typed")
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SignatureMaker.hands) { h in
                        Button { hand = h } label: {
                            HStack {
                                Text(typed.isEmpty ? (initials ? "AR" : "Your Name") : typed)
                                    .font(.custom(h.postScript, size: 30))
                                    .foregroundStyle(Color(red: 0.05, green: 0.1, blue: 0.45))
                                    .lineLimit(1)
                                Spacer()
                                Text(h.name).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 58)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(hand == h ? theme.accent : Color.primary.opacity(0.12), lineWidth: hand == h ? 2 : 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("signmaker.hand")
                    }
                }
            }
            .frame(height: 230)
        }
    }

    private var drawPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignaturePad(strokes: $strokes)
                .frame(height: 200)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1).padding(.horizontal, 30).padding(.bottom, 46)
                }
                .accessibilityIdentifier("signature.pad")
            HStack {
                Text("Sign with your trackpad or mouse.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { strokes = [] }.disabled(strokes.isEmpty)
            }
        }
    }

    private var photoPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign on white paper, take a photo in good light, and choose it here. Haven keeps the ink and drops the paper.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                if let photo {
                    Image(decorative: photo, scale: 2).resizable().scaledToFit().padding(16)
                } else if let photoProblem {
                    Text(photoProblem).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo").font(.system(size: 34)).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 170)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            Button("Choose a Photo…") { choosePhoto() }
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo of your \(noun) on paper"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        photo = SignatureMaker.fromPhoto(url)
        photoProblem = photo == nil ? "No ink found in that picture. Try one with darker ink on white paper." : nil
    }
}
