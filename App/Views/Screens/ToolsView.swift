import HavenCore
import SwiftUI

/// Every tool, grouped. Click one to pick files, or drop files on it. Right-click any file for the ones that fit it.
struct ToolsView: View {
    @Environment(\.theme) private var theme
    private var model: AppModel { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(title: "File Tools",
                           subtitle: "\(ToolID.allCases.count) tools for images, PDFs, video, audio and text. They all run on your Mac and make new files next to the originals.",
                           symbol: "wrench.and.screwdriver")
                TipBanner(id: "tools.intro", symbol: "cursorarrow.click.2", title: "Right-click is quicker",
                          message: "Right-click any file (or several) and choose Tools to see just the ones that fit. Undo takes away what a tool made.")
                ForEach(ToolGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: group.symbol).foregroundStyle(theme.accent)
                            SectionHeader(title: group.title, subtitle: groupNote(group))
                        }
                        // Not lazy: there are only a few dozen cards, and every one is there for VoiceOver and tests.
                        FlowLayout(spacing: 14, centered: false) {
                            ForEach(group.tools) { tool in ToolCard(tool: tool) }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("tools.group.\(group.rawValue)")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .background(theme.canvas)
        .onAppear { model.setVisible([]) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tools")
    }

    private func groupNote(_ group: ToolGroup) -> String? {
        switch group {
        case .ai: return "Whisper transcription, macOS translation and Apple Intelligence summaries"
        case .video: return "No extra software needed"
        default: return nil
        }
    }
}

struct ToolCard: View {
    let tool: ToolID
    @State private var targeted = false
    @Environment(\.theme) private var theme

    private var note: String? {
        switch tool {
        case .translate:
            if #unavailable(macOS 15.0) { return "Needs macOS 15" }
            return nil
        case .summarize: return Summarizer.unavailableReason == nil ? nil : "Needs Apple Intelligence"
        case .transcribe: return WhisperModels.shared.isReady ? nil : "One-time download"
        default: return nil
        }
    }

    var body: some View {
        Button { ToolActions.choose(tool) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title).fontWeight(.semibold)
                    Text(tool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note).font(.caption2.weight(.medium)).foregroundStyle(theme.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 236, height: 64, alignment: .topLeading)
            .cardStyle(theme, padding: 12)
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).strokeBorder(theme.accent, lineWidth: targeted ? 2.5 : 0))
            .interactiveCard()
        }
        .buttonStyle(.plain)
        .help("\(tool.choosePrompt), or drop files here")
        .dropDestination(for: URL.self) { urls, _ in
            ToolActions.dropped(urls, on: tool)
        } isTargeted: { targeted = $0 }
        .accessibilityIdentifier("tool.\(tool.rawValue)")
    }
}
