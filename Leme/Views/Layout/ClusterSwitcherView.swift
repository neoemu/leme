import SwiftUI

// MARK: - Cluster Switcher

struct ClusterSwitcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @Environment(SettingsStore.self) private var settingsStore

    @State private var isPopoverPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: Theme.Dimensions.spacing) {
                if let cluster = appState.activeCluster {
                    ClusterStatusIndicator(status: cluster.status)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(cluster.displayName)
                            .font(Theme.Fonts.subtitle)
                            .foregroundStyle(Theme.Colors.sidebarText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: Theme.Dimensions.smallSpacing) {
                            if let environment = settingsStore.environment(for: cluster) {
                                ClusterEnvironmentBadge(environment: environment)
                            }
                            if let version = cluster.serverVersion {
                                Text("v\(version)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.sidebarMutedText)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.sidebarMutedText)

                    Text("Select Cluster")
                        .font(Theme.Fonts.subtitle)
                        .foregroundStyle(Theme.Colors.sidebarMutedText)
                }

                Spacer(minLength: Theme.Dimensions.smallSpacing)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.sidebarMutedText)
            }
            .padding(.horizontal, Theme.Dimensions.spacing)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(activeClusterTooltip)
        .accessibilityLabel("Cluster switcher")
        .contextMenu {
            if let cluster = appState.activeCluster, cluster.status == .connected {
                Button("Disconnect from \(cluster.displayName)") {
                    Task {
                        await clusterViewModel.disconnect(clusterID: cluster.id, appState: appState)
                    }
                }
                Button("Refresh Namespaces") {
                    Task {
                        await clusterViewModel.refreshNamespaces(for: cluster.id, appState: appState)
                    }
                }
            }
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            ClusterSwitcherPopover(isPresented: $isPopoverPresented)
        }
    }

    private var activeClusterTooltip: String {
        guard let cluster = appState.activeCluster else {
            return "Select a cluster"
        }
        var text = "\(cluster.displayName) (\(cluster.status.rawValue))"
        if !cluster.clusterURL.isEmpty {
            text += "\nServer: \(cluster.clusterURL)"
        }
        if cluster.status == .error, let errorMsg = cluster.errorMessage {
            text += "\nError: \(errorMsg)"
        }
        return text
    }
}

// MARK: - Popover

private struct ClusterSwitcherPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @Environment(SettingsStore.self) private var settingsStore

    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var filteredClusters: [ClusterConnection] {
        guard !searchText.isEmpty else { return appState.clusters }
        return appState.clusters.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.clusters.count > 4 {
                HStack(spacing: Theme.Dimensions.spacing) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Filter clusters", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.sidebarItem)
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.spacing)

                Divider()
            }

            if filteredClusters.isEmpty {
                Text(appState.clusters.isEmpty ? "No clusters in kubeconfig" : "No matching clusters")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(.secondary)
                    .padding(Theme.Dimensions.padding)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredClusters) { cluster in
                            ClusterSwitcherRow(
                                cluster: cluster,
                                environment: settingsStore.environment(for: cluster),
                                isActive: cluster.id == appState.activeClusterID,
                                action: {
                                    select(cluster)
                                },
                                onDisconnect: cluster.status == .connected
                                    ? { disconnect(cluster) }
                                    : nil
                            )
                            .contextMenu {
                                contextMenuItems(for: cluster)
                            }
                        }
                    }
                    .padding(.vertical, Theme.Dimensions.smallSpacing)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 300)
    }

    private func select(_ cluster: ClusterConnection) {
        appState.selectCluster(cluster.id)
        if cluster.status == .disconnected || cluster.status == .error {
            Task {
                await clusterViewModel.connect(cluster: cluster, appState: appState)
            }
        }
        isPresented = false
    }

    private func disconnect(_ cluster: ClusterConnection) {
        Task {
            await clusterViewModel.disconnect(clusterID: cluster.id, appState: appState)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for cluster: ClusterConnection) -> some View {
        Menu("Environment") {
            Button {
                settingsStore.clearEnvironmentOverride(forContext: cluster.contextName)
            } label: {
                let detected = ClusterEnvironment.detect(from: cluster.displayName)
                Text("Automatic (\(detected?.rawValue ?? "none"))")
                if !settingsStore.hasOverride(forContext: cluster.contextName) {
                    Image(systemName: "checkmark")
                }
            }

            Divider()

            ForEach([ClusterEnvironment.production, .staging, .development, .test], id: \.self) { env in
                Button {
                    settingsStore.setEnvironmentOverride(env, forContext: cluster.contextName)
                } label: {
                    Text(env.rawValue)
                    if settingsStore.environmentOverrides[cluster.contextName] == env.rawValue {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                settingsStore.setEnvironmentOverride(nil, forContext: cluster.contextName)
            } label: {
                Text("None")
                if settingsStore.environmentOverrides[cluster.contextName] == SettingsStore.noEnvironmentSentinel {
                    Image(systemName: "checkmark")
                }
            }
        }

        Divider()

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

// MARK: - Row

private struct ClusterSwitcherRow: View {
    let cluster: ClusterConnection
    let environment: ClusterEnvironment?
    let isActive: Bool
    let action: () -> Void
    var onDisconnect: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            ClusterStatusIndicator(status: cluster.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(cluster.displayName)
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if cluster.status == .error, let errorMsg = cluster.errorMessage {
                    Text(errorMsg)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.failed)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Dimensions.smallSpacing)

            if let environment {
                ClusterEnvironmentBadge(environment: environment)
            }

            if let version = cluster.serverVersion {
                Text("v\(version)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let onDisconnect {
                Button(action: onDisconnect) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? Theme.Colors.failed : .secondary)
                }
                .buttonStyle(.plain)
                .help("Disconnect")
            }

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, 5)
        .background(isHovered ? Theme.Colors.tableSelectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .help(cluster.clusterURL.isEmpty ? cluster.displayName : cluster.clusterURL)
    }
}

// MARK: - Status Indicator

struct ClusterStatusIndicator: View {
    let status: ClusterConnectionStatus

    var body: some View {
        if status == .connecting {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }

    private var color: Color {
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
}

// MARK: - Environment Badge

struct ClusterEnvironmentBadge: View {
    let environment: ClusterEnvironment

    var body: some View {
        Text(environment.rawValue)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.18)))
    }

    private var color: Color {
        switch environment {
        case .production:
            return Theme.Colors.failed
        case .staging:
            return Theme.Colors.warning
        case .development:
            return Theme.Colors.running
        case .test:
            return Theme.Colors.succeeded
        }
    }
}
