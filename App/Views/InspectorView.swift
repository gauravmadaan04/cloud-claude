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
                VStack(spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                    Text("Select a file to see its details").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("inspector")
    }

    private func multi(_ items: [FileItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(items.count) items selected").font(.title3.weight(.semibold))
            Text("\(ByteSize.format(items.totalSize)) in total").foregroundStyle(.secondary)
            let kinds = Dictionary(grouping: items, by: \.kind).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, pair in
                Label("\(pair.1) \(pair.1 == 1 ? pair.0.displayName : pair.0.pluralName)", systemImage: pair.0.symbolName)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorDetail: View {
    let item: FileItem
    @Environment(\.theme) private var theme
    @State private var details = FileDetails()
    @State private var text: String?
    private var model: AppModel { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuickLookPreview(url: item.url)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline).textSelection(.enabled)
                    Text(item.kind.displayName + (item.size > 0 ? " · \(ByteSize.format(item.size))" : ""))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open") { NSWorkspace.shared.open(item.url) }
                    Button("Show in Finder") { model.revealInFinder([item]) }
                }
                .buttonStyle(.bordered)

                section("Information") {
                    row("Where", tildePath(item.parentPath))
                    row("Created", item.created.formatted(date: .abbreviated, time: .shortened))
                    row("Modified", item.modified.formatted(date: .abbreviated, time: .shortened))
                    if let added = item.added { row("Added", added.formatted(date: .abbreviated, time: .shortened)) }
                    if let opened = item.lastOpened { row("Last opened", opened.formatted(date: .abbreviated, time: .shortened)) }
                    ForEach(Array(details.rows.enumerated()), id: \.offset) { _, r in row(r.0, r.1) }
                }

                if let source = item.source {
                    section("Downloaded From") {
                        HStack(spacing: 8) {
                            SourceBadge(source: source, size: 22)
                            Text(source.name).fontWeight(.medium)
                        }
                        ForEach(item.whereFroms.prefix(2), id: \.self) { url in
                            if let u = URL(string: url), u.scheme?.hasPrefix("http") == true {
                                Link(url, destination: u).font(.caption).lineLimit(2).truncationMode(.middle)
                            } else {
                                Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }

                if !item.tags.isEmpty {
                    section("Tags") {
                        HStack { ForEach(item.tags, id: \.self) { Text("#\($0)").font(.callout).foregroundStyle(theme.accent) } }
                    }
                }

                if item.kind.hasReadableText {
                    section("Text") {
                        if let text, !text.isEmpty {
                            Text(String(text.prefix(1200)) + (text.count > 1200 ? "…" : ""))
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            Button {
                                model.copyText([item])
                            } label: { Label("Copy Text", systemImage: "text.quote") }
                                .buttonStyle(.bordered)
                        } else if text == nil {
                            ProgressView().controlSize(.small)
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

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
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
