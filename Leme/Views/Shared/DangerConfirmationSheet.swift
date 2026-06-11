import SwiftUI

/// A pending destructive action gated behind type-to-confirm (used on
/// production clusters instead of one-click confirmation dialogs).
struct PendingDangerAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// The exact text the user must type (usually the resource name).
    let confirmText: String
    let confirmLabel: String
    let handler: () -> Void
}

/// GitHub-style destructive confirmation: the action button stays disabled
/// until the user types the resource name.
struct DangerConfirmationSheet: View {
    let action: PendingDangerAction
    let clusterName: String
    let onDismiss: () -> Void

    @State private var typedText = ""
    @FocusState private var isFieldFocused: Bool

    private var isConfirmed: Bool {
        typedText == action.confirmText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.failed)
                Text("PRODUCTION CLUSTER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.Colors.failed)
                Spacer()
                Text(clusterName)
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(Theme.Dimensions.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Theme.Colors.errorBackground)
            )

            Text(action.title)
                .font(Theme.Fonts.title)

            Text(action.message)
                .font(Theme.Fonts.sidebarItem)
                .foregroundStyle(Theme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
                (Text("Type ") + Text(action.confirmText).bold().font(Theme.Fonts.monoSmall) + Text(" to confirm:"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                TextField(action.confirmText, text: $typedText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.monoSmall)
                    .focused($isFieldFocused)
                    .onSubmit {
                        if isConfirmed {
                            confirm()
                        }
                    }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button(action.confirmLabel, role: .destructive, action: confirm)
                    .disabled(!isConfirmed)
            }
        }
        .padding(Theme.Dimensions.sectionSpacing)
        .frame(width: 420)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func confirm() {
        action.handler()
        onDismiss()
    }
}
