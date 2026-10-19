import HavenCore
import SwiftUI

/// ⌘I: live preview plus everything Haven knows about the selected file.
struct InspectorView: View {
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }

    var body: some View {
        let selection = model.selectedItems
        Group {
            if let item = model.previewItem ?? selection.first {
                if selection.count > 1 && model.previewItem == nil {
                    multi(selection)
                } else {
                    InspectorDetail(item: item).id(item.id)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                        .frame(width: 72, height: 72)
                        .background(Color.primary.opacity(0.04), in: Circle())
                    Text("No Selection").font(.headline)
                    Text("Select a file to see its details, where it came from and the text inside it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("inspector")
    }

    private func multi(_ items: [FileItem]) -> some View {
        let kinds = Dictionary(grouping: items, by: \.kind).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { i, item in
                        ThumbnailView(item: item, side: 128, height: 100, cornerRadius: 10)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.cardBackground, lineWidth: 3))
                            .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                            .rotationEffect(.degrees(Double(i) * 7 - 7))
                            .offset(x: CGFloat(i) * 16 - 16, y: CGFloat(i) * 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(items.count) items selected").font(.title3.weight(.semibold))
                    Text("\(ByteSize.format(items.totalSize)) in total").foregroundStyle(.secondary)
                }
                InspectorSection(title: "Kinds", symbol: "square.stack.3d.up") {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { i, pair in
                        if i > 0 { Divider() }
                        HStack {
                            Label(pair.0.pluralName, systemImage: pair.0.symbolName)
                            Spacer()
                            Text("\(pair.1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(16)
        }
    }
}

struct InspectorDetail: View {
    let item: FileItem
    @Environment(\.theme) private var theme
    @State private var details = FileDetails()
    @State private var text: String?
    private var model: AppModel { .shared }

    /// Pages are better scrolled in Quick Look; everything else looks best as a big thumbnail.
    private var usesQuickLook: Bool {
        [.pdf, .document, .presentation, .spreadsheet, .text, .code].contains(item.kind) && !item.isCloudOnly
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: theme.headingDesign))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(item.kind.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.tint(for: item.kind))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.fill(for: item.kind), in: Capsule())
                        if item.size > 0 {
                            Text(ByteSize.format(item.size)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let s = item.source { SourceBadge(source: s, size: 20) }
                    }
                }
                actions

                InspectorSection(title: "Information", symbol: "info.circle") {
                    row("Where", tildePath(item.parentPath))
                    Divider()
                    row("Created", item.created.formatted(date: .abbreviated, time: .shortened))
                    Divider()
                    row("Modified", item.modified.formatted(date: .abbreviated, time: .shortened))
                    if let added = item.added {
                        Divider()
                        row("Added", added.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let opened = item.lastOpened {
                        Divider()
                        row("Last opened", opened.formatted(date: .abbreviated, time: .shortened))
                    }
                    ForEach(Array(details.rows.enumerated()), id: \.offset) { _, r in
                        Divider()
                        row(r.0, r.1)
                    }
                }

                if let source = item.source {
                    InspectorSection(title: "Downloaded From", symbol: "arrow.down.circle") {
                        HStack(spacing: 8) {
                            SourceBadge(source: source, size: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(source.name).fontWeight(.medium)
                                if let host = source.host { Text(host).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        ForEach(item.whereFroms.prefix(2), id: \.self) { url in
                            if let u = URL(string: url), u.scheme?.hasPrefix("http") == true {
                                Link(destination: u) {
                                    Label(url, systemImage: "link").labelStyle(.titleAndIcon)
                                }
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            } else {
                                Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }

                if !item.tags.isEmpty {
                    InspectorSection(title: "Tags", symbol: "tag") {
                        FlowLayout(spacing: 6, centered: false) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(theme.isPlayful ? theme.accent : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(theme.accent.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                if item.kind.hasReadableText {
                    InspectorSection(title: "Text Inside", symbol: "text.viewfinder") {
                        if let text, !text.isEmpty {
                            Text(String(text.prefix(1200)) + (text.count > 1200 ? "…" : ""))
                                .font(.system(size: 11.5))
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                model.copyText([item])
                            } label: { Label("Copy Text", systemImage: "doc.on.doc") }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        } else if text == nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Reading…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No text found").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }
            .padding(16)
        }
        .task {
            details = await MetadataReader.details(for: item)
            if item.kind.hasReadableText, !item.isCloudOnly {
                text = await LibraryStore.shared.text.text(for: item) ?? ""
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if usesQuickLook {
            QuickLookPreview(url: item.url)
                .frame(height: 230)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        } else {
            GeometryReader { geo in
                ThumbnailView(item: item, side: geo.size.width, height: 210, cornerRadius: 14)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .onTapGesture(count: 2) { model.preview(item, in: model.visibleItems) }
            }
            .frame(height: 210)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            InspectorAction(title: "Open", symbol: "arrow.up.forward.app") { NSWorkspace.shared.open(item.url) }
            InspectorAction(title: "Finder", symbol: "folder") { model.revealInFinder([item]) }
            InspectorAction(title: "Preview", symbol: "eye") { model.preview(item, in: model.visibleItems) }
            InspectorAction(title: "Trash", symbol: "trash", destructive: true) { model.trash([item], reason: "Moved by you") }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 86, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

/// A titled card in the inspector.
struct InspectorSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.05)))
        }
    }
}

/// Round action with a caption, like the buttons on a contact card.
private struct InspectorAction: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(destructive ? Color.red : (theme.isPlayful ? theme.accent : .primary))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill((destructive ? Color.red : theme.accent).opacity(hovering ? 0.18 : 0.1)))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(title)
    }
}
