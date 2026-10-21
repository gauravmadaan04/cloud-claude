import AppKit
import HavenCore
import NaturalLanguage
import PDFKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Translation)
import Translation
#endif

// MARK: Sign

/// Your signature, drawn once and kept in Haven's support folder for next time.
enum SignatureStore {
    static var url: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("signature.png") }

    static func load() -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func save(_ image: CGImage) {
        try? ImageTools.write(image, as: .png, to: url, props: [:])
    }
}

struct SignSheet: View {
    let request: ToolSheetRequest
    @State private var signature: CGImage? = SignatureStore.load()
    @State private var drawing = SignatureStore.load() == nil
    @State private var strokes: [[CGPoint]] = []
    @State private var placement: SignaturePlacement?
    @State private var width: CGFloat = 170
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSheetHeader(tool: request.tool, items: request.items,
                            note: drawing ? "Sign with your trackpad or mouse. It's kept on this Mac for next time."
                                : "Click where the signature goes. Drag the slider to size it.")
            if drawing {
                SignaturePad(strokes: $strokes)
                    .frame(height: 220)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .overlay(alignment: .bottomLeading) {
                        Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1).padding(.horizontal, 30).padding(.bottom, 50)
                    }
                    .accessibilityIdentifier("signature.pad")
                HStack {
                    Button("Clear") { strokes = [] }.disabled(strokes.isEmpty)
                    Spacer()
                    if signature != nil { Button("Cancel") { drawing = false } }
                    Button("Use This Signature") {
                        if let image = SignaturePad.render(strokes) {
                            SignatureStore.save(image)
                            signature = image
                            drawing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty)
                    .accessibilityIdentifier("signature.use")
                }
            } else if let signature {
                PlacementView(url: request.items[0].url, signature: signature, width: width, placement: $placement)
                    .frame(height: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("signature.document")
                HStack(spacing: 10) {
                    Button("Draw Again") { strokes = []; drawing = true }
                    Text("Size").foregroundStyle(.secondary)
                    Slider(value: $width, in: 80...320).frame(width: 160)
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save Signed Copy") {
                        guard let placement else { return }
                        var extras = ToolExtras()
                        extras.signature = placement
                        dismiss()
                        ToolRunner.shared.start(.signPDF, request.items, extras: extras)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(placement == nil)
                    .accessibilityIdentifier("signature.save")
                }
            }
        }
        .padding(22)
        .frame(width: 640)
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

    /// The strokes as a transparent picture, cropped to the ink, at twice the size for crisp printing.
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
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.1, blue: 0.45, alpha: 1))
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

/// The document, where a click places the signature (shown as a preview until it's saved).
struct PlacementView: NSViewRepresentable {
    let url: URL
    let signature: CGImage
    let width: CGFloat
    @Binding var placement: SignaturePlacement?

    final class PlacingPDFView: PDFView {
        var onClick: ((PDFPage, CGPoint) -> Void)?
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let page = page(for: point, nearest: false) else { return super.mouseDown(with: event) }
            onClick?(page, convert(point, to: page))
        }
    }

    final class Preview: PDFAnnotation {
        var image: CGImage?
        override func draw(with box: PDFDisplayBox, in context: CGContext) {
            guard let image else { return }
            context.draw(image, in: bounds)
        }
    }

    final class Coordinator {
        var preview: Preview?
        var last: (page: PDFPage, point: CGPoint)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlacingPDFView {
        let view = PlacingPDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.windowBackgroundColor
        view.onClick = { page, point in
            context.coordinator.last = (page, point)
            place(page, at: point, in: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ view: PlacingPDFView, context: Context) {
        // The size slider moved: keep the signature where it was.
        if let last = context.coordinator.last, let current = placement, abs(current.rect.width - width) > 0.5 {
            place(last.page, at: last.point, in: view, coordinator: context.coordinator)
        }
    }

    private func place(_ page: PDFPage, at point: CGPoint, in view: PDFView, coordinator: Coordinator) {
        let aspect = CGFloat(signature.height) / CGFloat(max(1, signature.width))
        let rect = CGRect(x: point.x - width / 2, y: point.y - width * aspect / 2, width: width, height: width * aspect)
        if let old = coordinator.preview { old.page?.removeAnnotation(old) }
        let preview = Preview(bounds: rect, forType: .stamp, withProperties: nil)
        preview.image = signature
        page.addAnnotation(preview)
        coordinator.preview = preview
        guard let doc = view.document else { return }
        let index = doc.index(for: page)
        DispatchQueue.main.async { placement = SignaturePlacement(page: index, rect: rect, image: signature) }
    }
}

// MARK: Transcribe

struct TranscribeSheet: View {
    let request: ToolSheetRequest
    @State private var language = "auto"
    @State private var toEnglish = false
    @State private var text = true
    @State private var subtitles = false
    @State private var choice = WhisperModel.recommended
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    private var models: WhisperModels { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: .transcribe, items: request.items)
            if models.isReady {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Language").foregroundStyle(.secondary)
                        Picker("Language", selection: $language) {
                            Text("Work it out").tag("auto")
                            Divider()
                            ForEach(Transcriber.languages, id: \.code) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    GridRow {
                        Text("Save as").foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Toggle("Text (.txt)", isOn: $text).accessibilityIdentifier("transcribe.text")
                            Toggle("Subtitles (.srt)", isOn: $subtitles).accessibilityIdentifier("transcribe.srt")
                        }
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Toggle("Also translate into English", isOn: $toEnglish)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Label("Saved next to each file. What's said becomes searchable in Haven. Nothing leaves your Mac.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                modelPicker
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Transcribe") { go() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!models.isReady || (!text && !subtitles))
                    .accessibilityIdentifier("transcribe.go")
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcription runs on your Mac with Whisper (open source). It needs a one-time download:")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(WhisperModel.allCases) { model in
                Button { choice = model } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: choice == model ? "largecircle.fill.circle" : "circle").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.title).fontWeight(.semibold)
                                if model == WhisperModel.recommended {
                                    Text("Recommended for this Mac").font(.caption).foregroundStyle(theme.accent)
                                }
                            }
                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .background(Color.primary.opacity(choice == model ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let downloading = models.downloading {
                HStack {
                    ProgressView(value: models.progress).tint(theme.accent)
                    Text("\(Int(models.progress * 100))% of \(ByteSize.format(downloading.bytes))").font(.caption).monospacedDigit()
                    Button("Stop") { models.cancelDownload() }.controlSize(.small)
                }
            } else {
                Button("Download \(choice.title) (\(ByteSize.format(choice.bytes)))") { models.download(choice) }
                    .accessibilityIdentifier("transcribe.download")
            }
        }
    }

    private func go() {
        var extras = ToolExtras()
        extras.model = models.current
        extras.language = language == "auto" ? nil : language
        extras.toEnglish = toEnglish
        extras.transcriptFormats = Set([text ? TranscriptFormat.text : nil, subtitles ? .subtitles : nil].compactMap { $0 })
        dismiss()
        ToolRunner.shared.start(.transcribe, request.items, extras: extras)
    }
}

// MARK: Reading documents for translation and summaries

enum DocumentReader {
    /// Subtitles keep their timings; everything else is plain text.
    static func read(_ item: FileItem) -> (text: String, cues: [Cue]?)? {
        if item.ext == "srt" || item.ext == "vtt" {
            guard let raw = try? String(contentsOf: item.url, encoding: .utf8) else { return nil }
            let cues = Subtitles.parse(raw)
            return cues.isEmpty ? nil : (Subtitles.plainText(cues), cues)
        }
        guard let text = TextExtractor.extract(item)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return (text, nil)
    }

    static func language(of text: String) -> String? {
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(2_000)))
        return r.dominantLanguage?.rawValue
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: Translate

@available(macOS 15.0, *)
struct TranslateSheet: View {
    let request: ToolSheetRequest
    @State private var targets: [Locale.Language] = []
    @State private var target = ""
    @State private var document: (text: String, cues: [Cue]?)?
    @State private var source: String?
    @State private var configuration: TranslationSession.Configuration?
    @State private var working = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: .translate, items: request.items,
                            note: "Translated by macOS on this Mac. \(document?.cues != nil ? "Subtitles keep their timings." : "Saved as a text file next to the original.")")
            if document == nil && problem == nil {
                ProgressView("Reading…").frame(maxWidth: .infinity)
            } else if document != nil {
                LabeledContent("From") { Text(source.map(DocumentReader.languageName) ?? "Worked out by macOS").foregroundStyle(.secondary) }
                Picker("Into", selection: $target) {
                    ForEach(targets, id: \.maximalIdentifier) { lang in
                        Text(DocumentReader.languageName(lang.minimalIdentifier)).tag(lang.minimalIdentifier)
                    }
                }
                .accessibilityIdentifier("translate.target")
            }
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
            if working { ProgressView().progressViewStyle(.linear).tint(theme.accent) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Translate") {
                    problem = nil
                    working = true
                    configuration = TranslationSession.Configuration(source: source.map { Locale.Language(identifier: $0) },
                                                                     target: Locale.Language(identifier: target))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(document == nil || target.isEmpty || working)
                .accessibilityIdentifier("translate.go")
            }
        }
        .padding(22)
        .frame(width: 460)
        .task { await load() }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
    }

    private func load() async {
        let item = request.items[0]
        let read = await Task.detached(priority: .userInitiated) { DocumentReader.read(item) }.value
        guard let read else {
            problem = "There's no text to translate in “\(item.name)”"
            return
        }
        document = read
        source = DocumentReader.language(of: read.text)
        let all = await LanguageAvailability().supportedLanguages
        targets = all.filter { $0.minimalIdentifier != source }
            .sorted { DocumentReader.languageName($0.minimalIdentifier) < DocumentReader.languageName($1.minimalIdentifier) }
        let preferred = Locale.preferredLanguages.first.map { Locale.Language(identifier: $0).minimalIdentifier }
        target = targets.first { $0.minimalIdentifier == preferred && preferred != source }?.minimalIdentifier
            ?? targets.first { $0.minimalIdentifier == (source == "en" ? "hi" : "en") }?.minimalIdentifier
            ?? targets.first?.minimalIdentifier ?? ""
    }

    private func translate(with session: TranslationSession) async {
        guard let document else { return }
        let item = request.items[0]
        let pieces = document.cues.map { $0.map(\.text) } ?? TextChunks.split(document.text, maxCharacters: 1_200)
        do {
            try await session.prepareTranslation()
            let requests = pieces.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
            var results = [String](repeating: "", count: pieces.count)
            for response in try await session.translations(from: requests) {
                if let i = response.clientIdentifier.flatMap(Int.init), i < results.count { results[i] = response.targetText }
            }
            let name = DocumentReader.languageName(target)
            let output: String
            let ext: String
            if var cues = document.cues {
                for i in cues.indices { cues[i].text = results[i] }
                output = Subtitles.srt(cues)
                ext = "srt"
            } else {
                output = results.joined(separator: "\n\n")
                ext = "txt"
            }
            let dest = ToolWork.destination(ToolNaming.tagged(item, name, ext: ext), in: item.parentPath)
            try output.write(to: dest, atomically: true, encoding: .utf8)
            ToolRunner.shared.finish("Translate", JobOutcome(made: [Made(from: item.path, to: dest.path)]), symbol: ToolID.translate.symbol,
                                     undo: AppModel.mainWindow?.undoManager)
            dismiss()
        } catch {
            problem = "Couldn't translate: \(error.localizedDescription)"
        }
        working = false
        configuration = nil
    }
}

// MARK: Summarize

enum Summarizer {
    /// Whether summaries work on this Mac, and if not, why.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "Summaries need a Mac with Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to get summaries."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again in a little while."
            default: return "Summaries aren't available on this Mac right now."
            }
        }
        #endif
        return "Summaries need macOS 26 with Apple Intelligence."
    }

    /// A short summary, made on this Mac. Long documents are summarized in parts, then the parts together.
    static func summarize(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var pieces = TextChunks.split(text, maxCharacters: 7_000)
            guard !pieces.isEmpty else { throw ToolError.failed("There's no text to summarize") }
            while true {
                var notes: [String] = []
                for piece in pieces {
                    try Task.checkCancellation()
                    let session = LanguageModelSession(instructions: """
                        You summarize documents for busy people. Write in plain English (or the document's own language). \
                        Use 3 to 6 short bullet points with the key facts, names, dates and numbers. No preamble.
                        """)
                    notes.append(try await session.respond(to: "Summarize this:\n\n\(piece)").content)
                }
                if notes.count == 1 { return notes[0].trimmingCharacters(in: .whitespacesAndNewlines) }
                pieces = TextChunks.split(notes.joined(separator: "\n\n"), maxCharacters: 7_000)
            }
        }
        #endif
        throw ToolError.unsupported(unavailableReason ?? "Summaries aren't available")
    }
}

struct SummarizeSheet: View {
    let request: ToolSheetRequest
    @State private var summary = ""
    @State private var working = true
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: .summarize, items: request.items, note: "Made by Apple Intelligence on this Mac.")
            if working {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading and summarizing…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let problem {
                Label(problem, systemImage: "info.circle").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                ScrollView {
                    Text(summary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("summary.text")
                }
                .frame(minHeight: 160, maxHeight: 340)
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack {
                if !summary.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                        AppModel.shared.showToast("Copied the summary", symbol: "doc.on.doc")
                    }
                    Button("Save as Text File") { save() }
                }
                Spacer()
                // Esc closes it too.
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 540)
        .task { await run() }
    }

    private func run() async {
        if let reason = Summarizer.unavailableReason {
            problem = reason
            working = false
            return
        }
        let item = request.items[0]
        let read = await Task.detached(priority: .userInitiated) { DocumentReader.read(item) }.value
        guard let text = read?.text else {
            problem = "There's no text to summarize in “\(item.name)”"
            working = false
            return
        }
        do {
            summary = try await Summarizer.summarize(text)
        } catch {
            problem = "Couldn't summarize: \(error.localizedDescription)"
        }
        working = false
    }

    private func save() {
        let item = request.items[0]
        let dest = ToolWork.destination(ToolNaming.tagged(item, "summary", ext: "txt"), in: item.parentPath)
        guard (try? summary.write(to: dest, atomically: true, encoding: .utf8)) != nil else { return }
        ToolRunner.shared.finish("Summarize", JobOutcome(made: [Made(from: item.path, to: dest.path)]), symbol: ToolID.summarize.symbol,
                                 undo: AppModel.mainWindow?.undoManager)
        dismiss()
    }
}
