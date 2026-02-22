import SwiftUI

struct MainLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                ContentAreaView()

                if appState.isBottomPanelOpen {
                    BottomPanelView()
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.isBottomPanelOpen)
            .inspector(isPresented: $appState.isDetailPanelOpen) {
                InspectorDetailView()
            }
            .inspectorColumnWidth(min: 300, ideal: 420, max: 800)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await clusterViewModel.loadContexts(appState: appState)
                    }
                } label: {
                    Label("Reload Kubeconfig", systemImage: "arrow.clockwise")
                }
                .help("Reload kubeconfig")

                Button {
                    appState.isDetailPanelOpen.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle inspector panel")

                Button {
                    // Settings action placeholder
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Settings")
            }
        }
        .overlay {
            if appState.isCommandPaletteOpen {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isCommandPaletteOpen)
    }
}
