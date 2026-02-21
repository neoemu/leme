import SwiftUI

struct MainLayout: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            HotbarView()

            Divider()

            SidebarView()

            Divider()

            VStack(spacing: 0) {
                ContentAreaView()

                if appState.isBottomPanelOpen {
                    Divider()
                    BottomPanelView()
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isBottomPanelOpen)
        .overlay {
            if appState.isCommandPaletteOpen {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isCommandPaletteOpen)
    }
}
