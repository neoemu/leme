import SwiftUI

@main
struct KlaroApp: App {
    @State private var appState = AppState()
    @State private var clusterViewModel: ClusterViewModel

    init() {
        let manager = ClusterManager()
        _clusterViewModel = State(initialValue: ClusterViewModel(clusterManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            MainLayout()
                .frame(
                    minWidth: Constants.minWindowWidth,
                    minHeight: Constants.minWindowHeight
                )
                .environment(appState)
                .environment(clusterViewModel)
                .task {
                    await clusterViewModel.loadContexts(appState: appState)
                }
        }
        .defaultSize(
            width: Constants.defaultWindowWidth,
            height: Constants.defaultWindowHeight
        )
        .commands {
            AppCommands(appState: appState)
        }
    }
}
