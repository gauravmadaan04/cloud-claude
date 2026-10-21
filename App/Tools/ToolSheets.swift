import AppKit
import AVFoundation
import AVKit
import HavenCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Picks the window a tool needs before it runs.
struct ToolSheetView: View {
    let request: ToolSheetRequest

    var body: some View {
        Group {
            switch request.tool {
            case .mergePDFs, .mergeVideos: MergeOrderSheet(request: request)
            case .organizePDF, .extractPDFPages: PDFPagesSheet(request: request)
            case .lockPDF, .unlockPDF: PasswordSheet(request: request)
            case .signPDF: SignSheet(request: request)
            case .trimVideo, .trimAudio: TrimSheet(request: request)
            case .transcribe: TranscribeSheet(request: request)
            case .translate:
                if #available(macOS 15.0, *) { TranslateSheet(request: request) } else {
                    UnavailableSheet(request: request, reason: "Translation needs macOS 15 or later.")
                }
            case .summarize: SummarizeSheet(request: request)
            default: ToolChoicesSheet(request: request)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolSheet")
    }
}

/// The title row every tool window shares.
struct ToolSheetHeader: View {
    let tool: ToolID
    let items: [FileItem]
    var note: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tool.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title)
                    .font(.system(size: 19, weight: .bold, design: theme.headingDesign))
                Text(note ?? (items.count == 1 ? items[0].name : "\(items.count) files"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}

struct UnavailableSheet: View {
    let request: ToolSheetRequest
    let reason: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ToolSheetHeader(tool: request.tool, items: request.items)
            Label(reason, systemImage: "info.circle")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: Choices (from the File Tools page)

struct ToolChoicesSheet: View {
    let request: ToolSheetRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        let choices = request.tool.choices(for: request.items)
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: request.tool, items: request.items)
            VStack(spacing: 6) {
                ForEach(choices.indices, id: \.self) { i in
                    Button {
                        dismiss()
                        ToolRunner.shared.start(request.tool, request.items, choice: choices[i].choice)
                    } label: {
                        HStack {
                            Text(choices[i].title).fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toolChoice.\(choices[i].title)")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

// MARK: Merge order

struct MergeOrderSheet: View {
    let request: ToolSheetRequest
    @State private var order: [FileItem]
    @Environment(\.dismiss) private var dismiss

    init(request: ToolSheetRequest) {
        self.request = request
        _order = State(initialValue: request.items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: request.tool, items: order, note: "Drag to change the order. The first one comes first.")
            List {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 22)
                        ThumbnailView(item: item, side: 30, cornerRadius: 5)
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(ByteSize.format(item.size)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 240)
            .accessibilityIdentifier("merge.list")
            HStack {
                Button("Sort by Name") { order.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.tool == .mergePDFs ? "Merge \(order.count) PDFs" : "Merge \(order.count) Videos") {
                    dismiss()
                    ToolRunner.shared.start(request.tool, order)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("merge.go")
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

// MARK: Passwords

struct PasswordSheet: View {
    let request: ToolSheetRequest
    @State private var password = ""
    @State private var again = ""
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    private var locking: Bool { request.tool == .lockPDF }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolSheetHeader(tool: request.tool, items: request.items,
                            note: locking ? "A copy that opens only with this password. The original stays as it is."
                                : "A copy that opens without a password.")
            SecureField(locking ? "New password" : "Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("password.field")
            if locking {
                SecureField("Type it again", text: $again)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("password.again")
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(locking ? "Add Password" : "Remove Password") { go() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || (locking && again.isEmpty))
                    .accessibilityIdentifier("password.go")
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func go() {
        if locking, password != again {
            problem = "The two passwords aren't the same"
            return
        }
        if !locking, let doc = PDFDocument(url: request.items[0].url), !doc.unlock(withPassword: password) {
            problem = "That password doesn't open it"
            return
        }
        var extras = ToolExtras()
        extras.password = password
        dismiss()
        ToolRunner.shared.start(request.tool, request.items, extras: extras)
    }
}

// MARK: Page organizer

struct PDFPagesSheet: View {
    let request: ToolSheetRequest
    @State private var pages: [PageEdit] = []
    @State private var selected: Set<Int> = []
    @State private var thumbs: [Int: NSImage] = [:]
    @State private var rangeText = ""
    @State private var dragging: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private var extracting: Bool { request.tool == .extractPDFPages }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 118, maximum: 140), spacing: 14)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSheetHeader(tool: request.tool, items: request.items,
                            note: extracting ? "Click the pages you want, or type them (like 1-3, 5)."
                                : "Drag pages to reorder. Select pages to turn them or take them out.")
            HStack(spacing: 8) {
                if extracting {
                    TextField("Pages, like 1-3, 5", text: $rangeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: rangeText) { _, text in
                            if let parsed = PageRange.parse(text, pageCount: pages.count) { selected = Set(parsed) }
                        }
                        .accessibilityIdentifier("pages.range")
                } else {
                    Button { turn(-90) } label: { Label("Rotate Left", systemImage: "rotate.left") }.disabled(selected.isEmpty)
                    Button { turn(90) } label: { Label("Rotate Right", systemImage: "rotate.right") }.disabled(selected.isEmpty)
                        .accessibilityIdentifier("pages.rotateRight")
                    Button(role: .destructive) { pages.removeAll { selected.contains($0.source) }; selected = [] } label: {
                        Label("Take Out", systemImage: "trash")
                    }
                    .disabled(selected.isEmpty || selected.count == pages.count)
                    .accessibilityIdentifier("pages.delete")
                }
                Spacer()
                Button(selected.count == pages.count ? "Select None" : "Select All") {
                    selected = selected.count == pages.count ? [] : Set(pages.map(\.source))
                }
            }
            .controlSize(.small)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(pages) { edit in
                        pageCell(edit)
                            .onDrag {
                                dragging = edit.source
                                return NSItemProvider(object: String(edit.source) as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: PageDropDelegate(target: edit.source, pages: $pages, dragging: $dragging))
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 300, maxHeight: .infinity)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Text(extracting ? "\(selected.count) of \(pages.count) pages" : "\(pages.count) pages")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(extracting ? "Save \(HavenFormat.count(selected.count, "Page")) as PDF" : "Save as New PDF") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(extracting ? selected.isEmpty : pages.isEmpty)
                    .accessibilityIdentifier("pages.save")
            }
        }
        .padding(22)
        .frame(width: 680, height: 600)
        .task { await load() }
    }

    private func pageCell(_ edit: PageEdit) -> some View {
        let isSelected = selected.contains(edit.source)
        return VStack(spacing: 6) {
            ZStack {
                if let image = thumbs[edit.source] {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(Double(edit.rotation)))
                        // A sideways page is as wide as an upright one is tall: shrink it to fit.
                        .scaleEffect(edit.rotation % 180 == 0 ? 1 : 0.8)
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
                }
            }
            .frame(width: 104, height: 130)
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.accent, lineWidth: isSelected ? 3 : 0))
            Text("Page \(edit.source + 1)").font(.caption).foregroundStyle(isSelected ? theme.accent : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) || extracting {
                if isSelected { selected.remove(edit.source) } else { selected.insert(edit.source) }
            } else {
                selected = isSelected && selected.count == 1 ? [] : [edit.source]
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(edit.source + 1)")
        .accessibilityIdentifier("page.\(edit.source + 1)")
        .accessibilityAddTraits(.isButton)
    }

    private func turn(_ degrees: Int) {
        for i in pages.indices where selected.contains(pages[i].source) {
            pages[i].rotation = ((pages[i].rotation + degrees) % 360 + 360) % 360
        }
    }

    private func save() {
        var extras = ToolExtras()
        extras.pages = extracting ? pages.filter { selected.contains($0.source) } : pages
        dismiss()
        ToolRunner.shared.start(request.tool, request.items, extras: extras)
    }

    private func load() async {
        let url = request.items[0].url
        let count = PDFTools.pageCount(url)
        pages = (0..<count).map { PageEdit(source: $0) }
        let images = await Task.detached(priority: .userInitiated) { () -> [Int: NSImage] in
            guard let doc = PDFDocument(url: url) else { return [:] }
            var out: [Int: NSImage] = [:]
            for i in 0..<min(doc.pageCount, 400) {
                if let page = doc.page(at: i) { out[i] = page.thumbnail(of: NSSize(width: 208, height: 260), for: .mediaBox) }
            }
            return out
        }.value
        thumbs = images
    }
}

/// Moves a page while it's dragged over another one.
struct PageDropDelegate: DropDelegate {
    let target: Int
    @Binding var pages: [PageEdit]
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target, let from = pages.firstIndex(where: { $0.source == d }),
              let to = pages.firstIndex(where: { $0.source == target }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            pages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: Trim

struct TrimSheet: View {
    let request: ToolSheetRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolSheetHeader(tool: request.tool, items: request.items, note: "Drag the yellow handles to the part you want, then click Trim.")
            TrimmingPlayer(url: request.items[0].url) { range in
                dismiss()
                guard let range else { return }
                var extras = ToolExtras()
                extras.timeRange = range
                ToolRunner.shared.start(request.tool, request.items, extras: extras)
            }
            .frame(width: 680, height: request.tool == .trimAudio ? 150 : 400)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(22)
    }
}

/// QuickTime's own trimming bar.
struct TrimmingPlayer: NSViewRepresentable {
    let url: URL
    let finished: (CMTimeRange?) -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        let item = AVPlayerItem(url: url)
        view.player = AVPlayer(playerItem: item)
        Task { @MainActor in
            for _ in 0..<100 where !view.canBeginTrimming {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard view.canBeginTrimming else {
                finished(nil)
                return
            }
            view.beginTrimming { result in
                guard result == .okButton else {
                    finished(nil)
                    return
                }
                let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
                let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
                finished(CMTimeRange(start: start, end: end))
            }
        }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
