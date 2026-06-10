import AppKit
import SwiftUI

/// Shuts down active Kubernetes clients before the process exits so the
/// underlying HTTPClients are released cleanly (their deinit asserts in debug
/// when not shut down).
final class KlaroAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var clusterManager: ClusterManager?
    nonisolated(unsafe) static var portForwardManager: PortForwardManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager = Self.clusterManager else { return .terminateNow }
        Task {
            // kubectl port-forward children outlive the app if not terminated.
            await MainActor.run {
                Self.portForwardManager?.stopAll()
            }
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
    @State private var portForwardManager: PortForwardManager

    init() {
        let manager = ClusterManager()
        KlaroAppDelegate.clusterManager = manager
        _clusterViewModel = State(initialValue: ClusterViewModel(clusterManager: manager))

        let forwards = PortForwardManager()
        KlaroAppDelegate.portForwardManager = forwards
        _portForwardManager = State(initialValue: forwards)
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
                .environment(portForwardManager)
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
