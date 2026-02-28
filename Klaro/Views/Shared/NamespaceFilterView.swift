import SwiftUI

struct NamespaceFilterView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Menu {
            Button("All Namespaces") {
                appState.selectedNamespace = nil
            }

            if !appState.availableNamespaces.isEmpty {
                Divider()

                ForEach(appState.availableNamespaces, id: \.self) { namespace in
                    Button(namespace) {
                        appState.selectedNamespace = namespace
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.sidebarMutedText)

                Text(appState.selectedNamespace ?? "All Namespaces")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(Theme.Colors.sidebarText)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.sidebarMutedText)
            }
            .padding(.horizontal, Theme.Dimensions.spacing)
            .padding(.vertical, Theme.Dimensions.smallSpacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }
}
