import HavenCore
import SwiftUI

/// Drops down under the search field while it's focused and empty: recent searches and a few ideas.
/// Rows are tap targets rather than buttons so they can never take keyboard focus from the field.
struct SearchSuggestionsView: View {
    @Bindable private var model = AppModel.shared
    @Environment(\.theme) private var theme
    private var prefs: Prefs { .shared }

    private let ideas = [
        "pdfs from last week", "screenshots over 5 MB", "photos from whatsapp", "big videos older than a year",
        "invoices from gmail", "zips in downloads",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !prefs.recentSearches.isEmpty {
                sectionTitle("Recent") {
                    Text("Clear")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { prefs.forgetSearches() } }
                        .accessibilityAddTraits(.isButton)
                }
                VStack(spacing: 1) {
                    ForEach(prefs.recentSearches.prefix(5), id: \.self) { text in
                        RecentSearchRow(text: text) { run(text) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                Divider().padding(.horizontal, 14)
            }
            sectionTitle("Try") { EmptyView() }
            FlowLayout(spacing: 7, centered: false) {
                ForEach(ideas, id: \.self) { idea in
                    IdeaChip(text: idea) { run(idea) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            Divider().padding(.horizontal, 14)
            HStack(spacing: 14) {
                hint("↓", "jump to results")
                hint("esc", "close")
                Spacer()
                hint(prefs.hotKey.display, "search from any app")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 470)
        .glassBackground(RoundedRectangle(cornerRadius: 18, style: .continuous), fallback: .thickMaterial)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.suggestions")
    }

    private func run(_ text: String) {
        model.searchText = text
        prefs.rememberSearch(text)
    }

    private func sectionTitle<A: View>(_ title: String, @ViewBuilder accessory: () -> A) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 7)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct RecentSearchRow: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let parsed = QueryParser.parse(text)
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if parsed.headline != parsed.text {
                Text(parsed.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "arrow.up.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? theme.accent.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct IdeaChip: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let symbol = QueryParser.parse(text).chips.first { $0.kind != .sort }?.symbol ?? "magnifyingglass"
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
            Text(text)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(hovering ? AnyShapeStyle(theme.onAccent) : AnyShapeStyle(.primary))
        .background(hovering ? AnyShapeStyle(theme.accent) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0 : 0.06)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
