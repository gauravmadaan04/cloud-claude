import HavenCore
import SwiftUI

struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let onCommit: (NSEvent.ModifierFlags) -> Void
    @FocusState private var fieldFocused: Bool

    private var theme: Theme { Theme(look: Prefs.shared.look) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Find a file, like “invoice pdf from gmail”", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular))
                    .focused($fieldFocused)
                    .accessibilityIdentifier("quicksearch.field")
                if !model.text.isEmpty {
                    Button { model.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, model.chips.isEmpty ? 14 : 8)

            if !model.chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.chips) { chip in ChipView(chip: chip) }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 10)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if model.text.isEmpty && !model.results.isEmpty {
                            sectionLabel("Recent")
                        }
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            if !model.text.isEmpty && model.results.count > 1 && index <= 1 {
                                sectionLabel(index == 0 ? "Top Hit" : "More Results")
                            }
                            QuickSearchRow(item: item, selected: index == model.selectedIndex,
                                           prominent: index == 0 && !model.text.isEmpty)
                                .id(item.id)
                                .onTapGesture(count: 2) {
                                    model.selectedIndex = index
                                    onCommit([])
                                }
                                .onTapGesture { model.selectedIndex = index }
                                .onDrag { NSItemProvider(object: item.url as NSURL) }
                        }
                        if model.results.isEmpty {
                            Text(model.text.isEmpty ? "Haven is still indexing…" : "No matches")
                                .foregroundStyle(.secondary)
                                .padding(30)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selectedIndex) { _, i in
                    if model.results.indices.contains(i) { proxy.scrollTo(model.results[i].id) }
                }
            }
            Divider()
            HStack(spacing: 14) {
                hint("↩", "Open")
                hint("⌘↩", "Show in Haven")
                hint("⌥↩", "Show in Finder")
                hint("⌘C", "Copy file")
                Spacer()
                hint("esc", "Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 680, height: 460)
        .background(VisualEffectBackground(material: .popover))
        .environment(\.theme, theme)
        .onChange(of: model.focusToken, initial: true) { _, _ in
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: LibraryStore.shared.text.version) { _, _ in
            // Text read from images while the panel is open can add matches.
            if !model.text.isEmpty { model.refresh(keepSelection: true) }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct QuickSearchRow: View {
    let item: FileItem
    let selected: Bool
    var prominent = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(item: item, side: prominent ? 52 : 38, cornerRadius: prominent ? 9 : 7)
                .overlay(RoundedRectangle(cornerRadius: prominent ? 9 : 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: prominent ? 15 : 13.5, weight: prominent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(selected ? theme.onAccent : Color.primary)
                Text("\(item.parentName) · \(fileSubtitle(item))")
                    .font(.caption)
                    .foregroundStyle(selected ? theme.onAccent.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let s = item.source { SourceBadge(source: s, size: 18) }
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.onAccent.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, prominent ? 8 : 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? theme.accent : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quicksearch.row.\(item.name)")
    }
}
