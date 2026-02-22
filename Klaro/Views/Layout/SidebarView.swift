import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Cluster selector (horizontal row of cluster icons)
            clusterSelector
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.spacing)

            Divider()

            // Cluster header + Namespace filter
            if appState.activeCluster != nil {
                clusterHeader
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.top, Theme.Dimensions.spacing)

                NamespaceFilterView()
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.vertical, Theme.Dimensions.spacing)
            }

            // Resource navigation list
            List(selection: $appState.sidebarSelection) {
                Label("Cluster Dashboard", systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarSelection.dashboard)

                Label("All Workloads", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.unifiedWorkloads)

                ForEach(ResourceCategory.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(category.resourceKinds) { kind in
                            Label(kind.pluralName, systemImage: kind.icon)
                                .tag(SidebarSelection.resource(kind))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .opacity(appState.activeCluster != nil ? 1.0 : 0.4)
            .allowsHitTesting(appState.activeCluster != nil)
        }
        .navigationTitle("Klaro")
        .onChange(of: appState.sidebarSelection) { _, _ in
            // Clear resource selection when navigating
            appState.selectedResourceID = nil
            appState.isDetailPanelOpen = false
        }
    }

    // MARK: - Cluster Selector

    private var clusterSelector: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
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
        }
    }

    // MARK: - Cluster Header

    @ViewBuilder
    private var clusterHeader: some View {
        if let cluster = appState.activeCluster {
            HStack(spacing: Theme.Dimensions.spacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.displayName)
                        .font(Theme.Fonts.subtitle)
                        .lineLimit(1)

                    if let version = cluster.serverVersion {
                        Text("v\(version)")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Spacer()

                statusDot(for: cluster.status)
            }
        }
    }

    private func statusDot(for status: ClusterConnectionStatus) -> some View {
        let tooltipText: String = {
            guard let cluster = appState.activeCluster else {
                return status.rawValue.capitalized
            }
            var text = "Status: \(status.rawValue.capitalized)"
            if !cluster.clusterURL.isEmpty {
                text += "\nServer: \(cluster.clusterURL)"
            }
            if let errorMsg = cluster.errorMessage, status == .error {
                text += "\nError: \(errorMsg)"
            }
            return text
        }()

        return Circle()
            .fill(colorForStatus(status))
            .frame(width: 8, height: 8)
            .help(tooltipText)
    }

    private func colorForStatus(_ status: ClusterConnectionStatus) -> Color {
        switch status {
        case .connected:
            return Theme.Colors.running
        case .connecting:
            return Theme.Colors.pending
        case .error:
            return Theme.Colors.failed
        case .disconnected:
            return Theme.Colors.terminated
        }
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
