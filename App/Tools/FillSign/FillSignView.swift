import AppKit
import HavenCore
import PDFKit
import SwiftUI

/// Opens Fill & Sign in its own window, one per document.
@MainActor
final class FillSignWindows: NSObject, NSWindowDelegate {
    static let shared = FillSignWindows()
    private var open: [NSWindow: FillEditor] = [:]

    func open(_ item: FileItem) {
        if let existing = open.first(where: { $0.value.source.path == item.path })?.key {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard let editor = FillEditor(source: item) else {
            let locked = PDFTools.isLocked(item.url)
            AppModel.shared.showToast(locked ? "“\(item.name)” has a password. Remove it first, then fill it in."
                : "Couldn't open “\(item.name)”", symbol: "exclamationmark.triangle")
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(1120, screen.width - 24), height: min(880, screen.height - 24))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Fill & Sign: \(item.name)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setAccessibilityIdentifier("fill.window")
        editor.onClose = { [weak window] in window?.close() }
        let host = NSHostingView(rootView: FillSignView(editor: editor).environment(\.theme, Theme(look: Prefs.shared.look)))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 860, height: 560)
        window.center()
        open[window] = editor
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let editor = open[sender], !editor.saved, !editor.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Close without saving?"
        alert.informativeText = "What you added to “\(editor.source.name)” will be lost. The original stays as it is."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Close")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        open[window] = nil
    }
}

/// Opens the Fill & Sign window when the tool is picked from a sheet-based path.
struct FillSignBridge: View {
    let request: ToolSheetRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            dismiss()
            if let item = request.items.first { FillSignWindows.shared.open(item) }
        }
    }
}

struct FillSignView: View {
    @Bindable var editor: FillEditor
    @Environment(\.theme) private var theme
    @State private var showDetails = false
    @State private var editingDetails = false
    @State private var showSignatures = false
    @State private var showInitials = false
    @State private var maker: MakerRequest?
    @FocusState private var textFocused: Bool
    private var prefs: Prefs { .shared }
    private var library: SignatureLibrary { .shared }

    struct MakerRequest: Identifiable {
        let id = UUID()
        let initials: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contextBar
            Divider()
            FillDocumentView(editor: editor)
            Divider()
            footer
        }
        .sheet(item: $maker) { request in
            SignatureMakerSheet(initials: request.initials) { saved in
                maker = nil
                if let saved { editor.tool = .signature(saved.id) }
            }
        }
        .onChange(of: editor.focusText) { textFocused = true }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("Select", "cursorarrow", .select, id: "fill.tool.select")
            toolButton("Text", "character.textbox", .text, id: "fill.tool.text")
            menuButton("My Details", "person.text.rectangle", active: isDetailTool, id: "fill.details") { showDetails = true }
                .popover(isPresented: $showDetails, arrowEdge: .bottom) { detailsMenu }
            toolButton("Date", "calendar", .date, id: "fill.tool.date")
            Menu {
                ForEach(DateStyle.allCases) { style in
                    Button(style.string(from: Date())) {
                        prefs.dateStyle = style
                        editor.tool = .date
                    }
                }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
            .help("How the date is written")
            .accessibilityIdentifier("fill.dateStyle")
            menuButton("Signature", "signature", active: isSignatureTool(initials: false), id: "fill.signature") { showSignatures = true }
                .popover(isPresented: $showSignatures, arrowEdge: .bottom) { signaturePicker(initials: false) }
            menuButton("Initials", "textformat", active: isSignatureTool(initials: true), id: "fill.initials") { showInitials = true }
                .popover(isPresented: $showInitials, arrowEdge: .bottom) { signaturePicker(initials: true) }
            separator
            ForEach(FillMark.allCases) { m in toolButton(m.title, m.symbol, .mark(m), id: "fill.tool.\(m.rawValue)", compact: true) }
            separator
            toolButton("White-Out", "rectangle.fill", .whiteout, id: "fill.tool.whiteout")
            toolButton("Redact", "eye.slash", .redact, id: "fill.tool.redact")
            separator
            ForEach(MarkupKind.allCases) { k in toolButton(k.title, k.symbol, .markup(k), id: "fill.tool.\(k.rawValue)", compact: true) }
            Spacer(minLength: 8)
            if editor.formFieldCount > 0 {
                Button {
                    editor.fillFormFromDetails()
                } label: {
                    Label("Fill Form", systemImage: "wand.and.stars")
                }
                .help("Put your details into the matching form fields")
                .accessibilityIdentifier("fill.autofill")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 30).padding(.horizontal, 3)
    }

    private var isDetailTool: Bool {
        if case .detail = editor.tool { return true }
        return false
    }

    private func isSignatureTool(initials: Bool) -> Bool {
        guard case .signature(let id) = editor.tool else { return false }
        return library.all.first { $0.id == id }?.initials == initials
    }

    private func toolButton(_ title: String, _ symbol: String, _ tool: FillTool, id: String, compact: Bool = false) -> some View {
        let on = editor.tool == tool
        return Button {
            editor.tool = on && tool != .select ? .select : tool
            editor.status = nil
            if tool != .select { editor.selectedID = nil }
        } label: {
            toolLabel(title, symbol, on: on, compact: compact)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func menuButton(_ title: String, _ symbol: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title, symbol, on: active, compact: false, chevron: true)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func toolLabel(_ title: String, _ symbol: String, on: Bool, compact: Bool, chevron: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(height: 18)
            if !compact {
                HStack(spacing: 2) {
                    Text(title).font(.system(size: 10.5))
                    if chevron { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)) }
                }
                .lineLimit(1)
            }
        }
        .frame(minWidth: compact ? 28 : 54)
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .foregroundStyle(on ? theme.accent : Color.primary)
        .background(on ? theme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: My Details

    private var detailsMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingDetails {
                MyDetailsForm { editingDetails = false }
            } else {
                Text("Click one, then click where it goes").font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                ForEach(PersonalDetails.Field.allCases) { field in
                    let value = prefs.personalDetails.value(field)
                    Button {
                        if value.isEmpty {
                            editingDetails = true
                        } else {
                            showDetails = false
                            editor.tool = .detail(field)
                            editor.selectedID = nil
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: field.symbol).frame(width: 18).foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(field.title).font(.caption).foregroundStyle(.secondary)
                                Text(value.isEmpty ? "Not set" : value.replacingOccurrences(of: "\n", with: ", "))
                                    .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail.\(field.rawValue)")
                }
                Divider().padding(.vertical, 4)
                Button("Edit My Details…") { editingDetails = true }
                    .accessibilityIdentifier("details.edit")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Signatures

    private func signaturePicker(initials: Bool) -> some View {
        let list = initials ? library.initialsList : library.signatures
        return VStack(alignment: .leading, spacing: 8) {
            Text(initials ? "Your initials" : "Your signatures").font(.headline)
            if list.isEmpty {
                Text(initials ? "None yet. Make your initials once and use them on every page." : "None yet. Make one once and use it on every form.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list) { s in
                HStack {
                    Button {
                        editor.tool = .signature(s.id)
                        editor.selectedID = nil
                        if initials { showInitials = false } else { showSignatures = false }
                    } label: {
                        Image(decorative: s.image, scale: 2)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: initials ? 34 : 48)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(initials ? "initials.saved" : "signature.saved")
                    Button { library.remove(s) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete")
                }
            }
            Divider()
            Button(initials ? "New Initials…" : "New Signature…") {
                if initials { showInitials = false } else { showSignatures = false }
                maker = MakerRequest(initials: initials)
            }
            .accessibilityIdentifier(initials ? "initials.new" : "signature.new")
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: The selected item

    @ViewBuilder
    private var contextBar: some View {
        HStack(spacing: 10) {
            if let item = editor.selected {
                switch item.content {
                case .text:
                    TextField("Type here", text: Binding(get: { selectedText }, set: { editor.setText($0) }), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .frame(maxWidth: 360)
                        .focused($textFocused)
                        .accessibilityIdentifier("fill.text")
                    sizeButtons(item)
                    inkPicker
                case .mark:
                    sizeButtons(item)
                    inkPicker
                case .image(_, let initials):
                    Text(initials ? "Initials" : "Signature").foregroundStyle(.secondary)
                    sizeButtons(item)
                case .whiteout, .redaction:
                    Text(item.content.isRedaction ? "Redaction: removed for good when you save" : "White-out")
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) { editor.deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityIdentifier("fill.delete")
            } else {
                Image(systemName: editor.status == nil ? "info.circle" : "checkmark.circle")
                    .foregroundStyle(editor.status == nil ? Color.secondary : theme.accent)
                Text(editor.status ?? editor.tool.hint)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("fill.status")
            }
            Spacer()
            Button { editor.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
                .help("Take back the last thing you added, moved or deleted")
                .accessibilityIdentifier("fill.undo")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private var selectedText: String {
        if case .text(let t) = editor.selected?.content { return t }
        return ""
    }

    private func sizeButtons(_ item: FillItem) -> some View {
        HStack(spacing: 2) {
            Button { editor.scale(item.id, by: 1 / 1.15) } label: { Image(systemName: "minus") }.help("Smaller")
            Button { editor.scale(item.id, by: 1.15) } label: { Image(systemName: "plus") }.help("Bigger")
            if item.content.isText {
                Text("\(Int(item.fontSize.rounded())) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40)
            }
        }
    }

    private var inkPicker: some View {
        Picker("Colour", selection: Binding(get: { editor.selected?.ink ?? prefs.fillInk }, set: { editor.setInk($0) })) {
            ForEach(FillInk.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
    }

    // MARK: Saving

    private var footer: some View {
        HStack(spacing: 12) {
            if editor.formFieldCount > 0 {
                Toggle("Lock the form so answers can't be changed", isOn: $editor.lockForm)
                    .toggleStyle(.checkbox)
                    .help("Recommended when you send the form. Pages you added to are always locked.")
                    .accessibilityIdentifier("fill.lock")
            } else {
                Label("Saved as a new copy. The original stays as it is.", systemImage: "doc.on.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { editor.onClose?() }
            Button(editor.items.contains { $0.content.isSignature } ? "Save Signed Copy" : "Save Copy") { editor.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(editor.isEmpty && editor.formFieldCount == 0)
                .accessibilityIdentifier("fill.save")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Your name, email, phone and so on, kept on this Mac for forms.
struct MyDetailsForm: View {
    var onDone: () -> Void
    @State private var details = Prefs.shared.personalDetails
    @State private var style = Prefs.shared.dateStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Details").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                row("Name", $details.name, "details.name")
                row("Initials", $details.initials, "details.initials", placeholder: details.effectiveInitials.isEmpty ? "From your name" : details.effectiveInitials)
                row("Email", $details.email, "details.email")
                row("Phone", $details.phone, "details.phone")
                GridRow {
                    Text("Address").foregroundStyle(.secondary)
                    TextField("", text: $details.address, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("details.address")
                }
                row("Company", $details.company, "details.company")
                GridRow {
                    Text("Date").foregroundStyle(.secondary)
                    Picker("Date", selection: $style) {
                        ForEach(DateStyle.allCases) { Text($0.string(from: Date())).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            Text("Kept on this Mac only.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") {
                    Prefs.shared.personalDetails = details
                    Prefs.shared.dateStyle = style
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("details.save")
            }
        }
    }

    private func row(_ title: String, _ value: Binding<String>, _ id: String, placeholder: String = "") -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .accessibilityIdentifier(id)
        }
    }
}
