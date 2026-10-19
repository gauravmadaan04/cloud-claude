import HavenCore
import SwiftUI

/// Downloads grouped by where they came from.
struct SourcesView: View {
    @Environment(\.theme) private var theme
    private var store: LibraryStore { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        let sources = store.derived.sources
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Downloaded From", subtitle: "Every download, grouped by where it came from", symbol: "arrow.down.circle")
                TipBanner(id: "sources.intro", symbol: "info.circle", title: "How Haven knows",
                          message: "Browsers, mail and chat apps note where each download came from. Haven reads that note: nothing is looked up online. Use the “From” filter on any list to narrow it down.")
                if sources.isEmpty {
                    EmptyStateView(symbol: "arrow.down.circle", title: store.hasLoaded ? "No downloads with a source yet" : "Looking…",
                                   message: "Files you download with Safari, Chrome, Firefox, Mail, WhatsApp, Slack and others will be grouped here.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)], spacing: 16) {
                        ForEach(sources) { s in
                            Button { model.navigate(to: .source(s.source.id)) } label: {
                                SourceCard(summary: s)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("source.card.\(s.source.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .background(theme.canvas)
        .onAppear { model.setVisible([]) }
    }
}

struct SourceCard: View {
    let summary: SourceSummary
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SourceBadge(source: summary.source, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.source.name)
                        .font(.system(.headline, design: theme.headingDesign))
                        .lineLimit(1)
                    Text("\(HavenFormat.count(summary.count, "file")) · \(ByteSize.format(summary.bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(HavenFormat.ago(summary.latest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(summary.preview) { item in
                    ThumbnailView(item: item, side: 72, height: 56, cornerRadius: 8)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(theme, padding: 14)
        .interactiveCard(tint: theme.sourceColor(summary.source.tint))
    }
}
