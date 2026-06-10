import AppKit
import SwiftUI

/// Shuts down active Kubernetes clients before the process exits so the
/// underlying HTTPClients are released cleanly (their deinit asserts in debug
/// when not shut down).
final class KlaroAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var clusterManager: ClusterManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager = Self.clusterManager else { return .terminateNow }
        Task {
            await manager.disconnectAll()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct KlaroApp: App {
    @NSApplicationDelegateAdaptor(KlaroAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var clusterViewModel: ClusterViewModel

    init() {
        let manager = ClusterManager()
        KlaroAppDelegate.clusterManager = manager
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
                    clusterViewModel.startKubeconfigWatcher(appState: appState)
                }
        }
        .defaultSize(
            width: Constants.defaultWindowWidth,
            height: Constants.defaultWindowHeight
        )
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView()
        }
    }
}
