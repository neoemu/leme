import SwiftUI

struct HotbarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    var body: some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            // Home button
            Button {
                appState.activeClusterID = nil
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(appState.activeClusterID == nil ? Theme.Colors.accent : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Dimensions.spacing)

            Divider()
                .padding(.horizontal, 8)

            // Cluster buttons
            ForEach(appState.clusters) { cluster in
                Button {
                    appState.selectCluster(cluster.id)
                    if cluster.status == .disconnected {
                        Task {
                            await clusterViewModel.connect(cluster: cluster, appState: appState)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(appState.activeClusterID == cluster.id ? Theme.Colors.accent : Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        cluster.status == .error ? Theme.Colors.failed : Color.clear,
                                        lineWidth: 2
                                    )
                                    .frame(width: 36, height: 36)
                            )
                            .opacity(cluster.status == .connecting ? 0.7 : 1.0)
                            .animation(
                                cluster.status == .connecting
                                    ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                    : .default,
                                value: cluster.status == .connecting
                            )

                        if cluster.status == .connecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(cluster.initials)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(appState.activeClusterID == cluster.id ? .white : .primary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(clusterTooltip(for: cluster))
                .contextMenu {
                    if cluster.status == .connected {
                        Button("Disconnect") {
                            Task {
                                await clusterViewModel.disconnect(clusterID: cluster.id, appState: appState)
                            }
                        }
                        Button("Refresh Namespaces") {
                            Task {
                                await clusterViewModel.refreshNamespaces(for: cluster.id, appState: appState)
                            }
                        }
                    } else {
                        Button("Connect") {
                            Task {
                                await clusterViewModel.connect(cluster: cluster, appState: appState)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Reload kubeconfig button
            Button {
                Task {
                    await clusterViewModel.loadContexts(appState: appState)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reload kubeconfig")

            // Settings button
            Button {
                // Settings action placeholder
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, Theme.Dimensions.spacing)
        }
        .frame(width: Theme.Dimensions.hotbarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.hotbarBackground)
    }

    private func clusterTooltip(for cluster: ClusterConnection) -> String {
        var text = cluster.displayName
        text += " (\(cluster.status.rawValue))"
        if cluster.status == .error, let errorMsg = cluster.errorMessage {
            text += "\nError: \(errorMsg)"
        }
        return text
    }
}
