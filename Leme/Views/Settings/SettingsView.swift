import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @Environment(SettingsStore.self) private var settingsStore

    @AppStorage(SettingsStore.autoRefreshIntervalKey) private var autoRefreshInterval = 30.0
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalShellPath") private var terminalShellPath = "/bin/zsh"

    @State private var isReloadingContexts = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
            clusterSettings
                .tabItem { Label("Clusters", systemImage: "server.rack") }
            terminalSettings
                .tabItem { Label("Terminal", systemImage: "terminal") }
        }
        .frame(width: 520, height: 360)
    }

    // MARK: - General

    private var generalSettings: some View {
        @Bindable var settingsStore = settingsStore

        return Form {
            Section("Kubeconfig") {
                HStack(spacing: Theme.Dimensions.spacing) {
                    TextField("Path", text: $settingsStore.kubeconfigPath)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.monoSmall)

                    Button("Browse…") {
                        browseForKubeconfig()
                    }
                }

                HStack {
                    Text("Changing the path requires reloading contexts (disconnects active clusters).")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(isReloadingContexts ? "Reloading…" : "Reload Contexts") {
                        isReloadingContexts = true
                        Task {
                            await clusterViewModel.applyKubeconfigPathChange(appState: appState)
                            isReloadingContexts = false
                        }
                    }
                    .disabled(isReloadingContexts)
                }
            }

            Section("Auto-Refresh") {
                Picker("Fallback resync interval", selection: $autoRefreshInterval) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("Disabled").tag(0.0)
                }

                Text("Live updates come from the watch stream; this is only the safety-net full reload.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Clusters

    private var clusterSettings: some View {
        Form {
            Section("Environment Overrides") {
                if settingsStore.environmentOverrides.isEmpty {
                    Text("No manual overrides. Environments are detected from context names (prod, stg, hml, dev, qa…). Right-click a cluster in the switcher to override.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settingsStore.environmentOverrides.sorted(by: { $0.key < $1.key }), id: \.key) { contextName, value in
                        HStack {
                            Text(contextName)
                                .font(Theme.Fonts.monoSmall)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text(value == SettingsStore.noEnvironmentSentinel ? "None" : value)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(.secondary)

                            Button("Reset") {
                                settingsStore.clearEnvironmentOverride(forContext: contextName)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Terminal

    private var terminalSettings: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $terminalFontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: $terminalFontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }
            }

            Section("Shell") {
                TextField("Shell Path", text: $terminalShellPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    private func browseForKubeconfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(
            fileURLWithPath: (settingsStore.kubeconfigPath as NSString).expandingTildeInPath
        ).deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.kubeconfigPath = url.path
        }
    }
}
