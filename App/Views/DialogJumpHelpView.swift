import SwiftUI

/// Explains the one permission the Open/Save jump needs, with buttons that go straight there.
struct DialogJumpHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var allowed = DialogJump.isAllowed

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "macwindow.badge.plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text("Jump into Open and Save dialogs")
                    .font(.system(size: 20, weight: .bold, design: theme.headingDesign))
            }
            Text("When an app shows an Open or Save dialog, open Quick Search (\(Prefs.shared.hotKey.display)), pick a folder or file and press ⌃↩. Haven types the path into the dialog's Go to Folder box for you.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To press those keys, macOS asks you to allow Haven under Privacy & Security › Accessibility. Haven only types there when you press ⌃↩.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if allowed {
                Label("Allowed. You're all set.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            HStack {
                Button("Open Accessibility Settings") { DialogJump.openAccessibilitySettings() }
                Button("Ask macOS") { DialogJump.askForPermission() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            // Notice when permission is given while this is open.
            while !Task.isCancelled && !allowed {
                try? await Task.sleep(for: .seconds(1))
                allowed = DialogJump.isAllowed
            }
        }
        .accessibilityIdentifier("dialogJump.help")
    }
}
