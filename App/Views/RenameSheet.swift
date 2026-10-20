import HavenCore
import SwiftUI

/// Rename one file or many: presets, a pattern with tokens, find & replace, and a live preview of every new name.
struct RenameSheet: View {
    let items: [FileItem]

    enum Preset: String, CaseIterable, Identifiable {
        case smart, addDate, number, findReplace, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .smart: return "Smart Names"
            case .addDate: return "Add Date"
            case .number: return "Number"
            case .findReplace: return "Find & Replace"
            case .custom: return "Custom"
            }
        }
        var pattern: String? {
            switch self {
            case .smart: return "{date} {title}"
            case .addDate: return "{date} {name}"
            case .number: return "{name} {n}"
            case .findReplace: return "{name}"
            case .custom: return nil
            }
        }
    }

    struct Token: Identifiable {
        let label: String
        let code: String
        let help: String
        var id: String { code }
    }

    static let tokens = [
        Token(label: "Name", code: "{name}", help: "The current name"),
        Token(label: "Title from text", code: "{title}", help: "A title Haven reads in the file (screenshots, photos, PDFs, documents)"),
        Token(label: "Date", code: "{date}", help: "2026-10-12, from the date you pick below"),
        Token(label: "Time", code: "{time}", help: "14.05"),
        Token(label: "Number", code: "{n}", help: "1, 2, 3…"),
        Token(label: "001", code: "{n:3}", help: "001, 002, 003…"),
        Token(label: "Source", code: "{source}", help: "Where it was downloaded from"),
        Token(label: "Folder", code: "{folder}", help: "The folder it's in"),
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.undoManager) private var undoManager
    @State private var template = RenameTemplate()
    @State private var preset: Preset = .custom
    @State private var changes: [RenameChange] = []
    @State private var planned = false
    @FocusState private var patternFocused: Bool

    private var changing: [RenameChange] { changes.filter(\.isChange) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(items.count == 1 ? "Rename “\(items[0].name)”" : "Rename \(HavenFormat.count(items.count, "file"))")
                .font(.system(size: 20, weight: .bold, design: theme.headingDesign))
            Picker("Preset", selection: $preset) {
                ForEach(Preset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("rename.preset")

            VStack(alignment: .leading, spacing: 8) {
                TextField("New name", text: $template.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($patternFocused)
                    .accessibilityIdentifier("rename.pattern")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.tokens) { token in
                            Button(token.label) { insert(token.code) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(token.help)
                                .accessibilityIdentifier("rename.token.\(token.label)")
                        }
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Find").foregroundStyle(.secondary)
                    TextField("Text to find", text: $template.find)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("rename.find")
                    Text("Replace with").foregroundStyle(.secondary)
                    TextField("Nothing", text: $template.replace)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("rename.replace")
                }
                GridRow {
                    Text("Date").foregroundStyle(.secondary)
                    Picker("Date", selection: $template.dateField) {
                        ForEach(RenameTemplate.DateField.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    Text("Letters").foregroundStyle(.secondary)
                    Picker("Letters", selection: $template.caseStyle) {
                        ForEach(RenameTemplate.CaseStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Numbers from").foregroundStyle(.secondary)
                    Stepper(value: $template.counterStart, in: 0...99_999) {
                        Text("\(template.counterStart)").monospacedDigit()
                    }
                    Color.clear.gridCellColumns(2).frame(height: 1)
                }
            }
            .font(.callout)

            preview
            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rename.summary")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(changing.count <= 1 ? "Rename" : "Rename \(changing.count) Files") {
                    // The main window owns ⌘Z (this sheet closes now).
                    FileOps.shared.rename(changes, undoManager: AppModel.mainWindow?.undoManager ?? undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(changing.isEmpty || !planned)
                .accessibilityIdentifier("rename.apply")
            }
        }
        .padding(22)
        .frame(width: 660, height: 620)
        .onAppear(perform: start)
        .onChange(of: preset) { _, p in
            if let pattern = p.pattern {
                template.pattern = pattern
                if p != .findReplace {
                    template.find = ""
                    template.replace = ""
                }
            }
        }
        .onChange(of: template.pattern) { _, pattern in
            if let p = preset.pattern, p != pattern { preset = .custom }
        }
        .task(id: template) {
            // A moment's pause while typing, so long lists aren't planned on every key.
            if planned && items.count > 300 { try? await Task.sleep(for: .milliseconds(150)) }
            let result = await RenameService.plan(items, template: template)
            if Task.isCancelled { return }
            changes = result
            planned = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rename.sheet")
    }

    private var preview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(changes.prefix(1000).enumerated()), id: \.element.id) { index, change in
                    HStack(spacing: 10) {
                        Text(change.item.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(change.newName)
                            .fontWeight(change.isChange ? .medium : .regular)
                            .foregroundStyle(change.isChange ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("rename.new.\(index)")
                        if change.adjusted {
                            Image(systemName: "number.circle")
                                .foregroundStyle(theme.accent)
                                .help("A number was added: the name was already taken in this folder")
                        }
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(index % 2 == 1 ? Color.primary.opacity(0.035) : .clear)
                }
                if changes.count > 1000 {
                    Text("…and \(changes.count - 1000) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityIdentifier("rename.preview")
    }

    private var summary: String {
        guard planned else { return "Working out the new names…" }
        let n = changing.count
        if n == 0 { return "Nothing changes yet" }
        var s = n == 1 ? "1 file will be renamed" : "\(n) files will be renamed"
        let adjusted = changes.filter(\.adjusted).count
        if adjusted > 0 { s += " · \(adjusted) got a number to stay unique" }
        let same = changes.count - n
        if same > 0 { s += " · \(same) stay as they are" }
        return s
    }

    private func start() {
        if items.count == 1 {
            // One file: just type the new name (its extension stays).
            template.pattern = RenamePlanner.split(items[0]).base
            preset = .custom
        } else if items.contains(where: { $0.kind.hasReadableText }) {
            preset = .smart
            template.pattern = Preset.smart.pattern!
        } else {
            preset = .addDate
            template.pattern = Preset.addDate.pattern!
        }
        patternFocused = true
    }

    private func insert(_ code: String) {
        let p = template.pattern
        template.pattern = p.isEmpty || p.hasSuffix(" ") ? p + code : p + " " + code
    }
}
