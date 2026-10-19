import HavenCore
import SwiftUI

/// Everything Haven moved or trashed, with Undo.
struct ActivityView: View {
    @Environment(\.theme) private var theme
    private var ops: FileOps { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PageHeader(title: "Activity", subtitle: "What Haven moved or put in the Trash. Undo anything.", symbol: "clock.arrow.circlepath")
                    if !ops.activity.isEmpty {
                        Button("Clear History") { ops.clearHistory() }.buttonStyle(.borderless)
                    }
                }
                if ops.activity.isEmpty {
                    EmptyStateView(symbol: "clock.arrow.circlepath", title: "Nothing yet",
                                   message: "When you clean up, trash duplicates or a rule files something away, it's listed here so you can undo it.")
                        .frame(minHeight: 300)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(ops.activity) { entry in
                            row(entry)
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

    private func row(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(entry))
                .font(.title3)
                .foregroundStyle(entry.undone ? Color.secondary : theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .fontWeight(.medium)
                    .strikethrough(entry.undone)
                Text("\(entry.reason) · \(HavenFormat.friendlyDate(entry.date))\(entry.totalBytes > 0 ? " · \(ByteSize.format(entry.totalBytes))" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.undone {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else if ops.canUndo(entry) {
                Button {
                    ops.undo(entry.id)
                } label: {
                    Label(entry.action == .trashed ? "Put Back" : "Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("activity.undo")
            }
            if entry.action != .trashed, let first = entry.moves.first, FileManager.default.fileExists(atPath: first.to) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(entry.moves.map { URL(fileURLWithPath: $0.to) })
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .cardStyle(theme, padding: 12)
    }

    private func symbol(_ e: ActivityEntry) -> String {
        switch e.action {
        case .trashed: return "trash"
        case .moved: return "folder.badge.plus"
        case .restored: return "arrow.uturn.backward.circle"
        }
    }
}
