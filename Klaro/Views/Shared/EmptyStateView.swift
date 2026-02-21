import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var secondaryMessage: String?
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Dimensions.spacing * 3) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.tertiaryText)
                .opacity(0.7)

            VStack(spacing: Theme.Dimensions.spacing) {
                Text(title)
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Text(message)
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                if let secondaryMessage {
                    Text(secondaryMessage)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .opacity(0.8)
                }
            }

            if let retryAction {
                Button {
                    retryAction()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(Theme.Fonts.sidebarItem)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
