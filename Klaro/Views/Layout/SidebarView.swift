import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredKind: ResourceKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cluster header
            clusterHeader
                .padding(Theme.Dimensions.padding)

            Divider()

            // Namespace filter
            NamespaceFilterView()
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.spacing)

            Divider()

            // Resource categories
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Dashboard item
                    dashboardItem
                        .padding(.horizontal, Theme.Dimensions.padding)
                        .padding(.vertical, 2)

                    Divider()
                        .padding(.horizontal, Theme.Dimensions.padding)
                        .padding(.vertical, 2)

                    ForEach(ResourceCategory.allCases) { category in
                        categorySection(category)
                    }
                }
                .padding(.vertical, Theme.Dimensions.spacing)
            }
            .opacity(appState.activeCluster != nil ? 1.0 : 0.4)
            .allowsHitTesting(appState.activeCluster != nil)
        }
        .frame(width: Theme.Dimensions.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.sidebarBackground)
    }

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
        } else {
            Text("No Cluster Selected")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(Theme.Colors.secondaryText)
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

    private var dashboardItem: some View {
        let isSelected = appState.showDashboard

        return Button {
            appState.showDashboard = true
            appState.showUnifiedWorkloads = false
            appState.selectedResourceID = nil
            appState.isDetailPanelOpen = false
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .frame(width: Theme.Dimensions.iconSize)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : .secondary)

                Text("Cluster Dashboard")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, Theme.Dimensions.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func categorySection(_ category: ResourceCategory) -> some View {
        DisclosureGroup {
            if category == .workloads {
                allWorkloadsItem
            }
            ForEach(category.resourceKinds) { kind in
                sidebarItem(for: kind)
            }
        } label: {
            HStack {
                Label(category.rawValue, systemImage: category.icon)
                    .font(Theme.Fonts.sidebarHeader)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                Text("\(category.resourceKinds.count)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, 2)
    }

    private var allWorkloadsItem: some View {
        let isSelected = appState.showUnifiedWorkloads

        return Button {
            appState.showDashboard = false
            appState.showUnifiedWorkloads = true
            appState.selectedResourceID = nil
            appState.isDetailPanelOpen = false
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "square.grid.2x2")
                    .frame(width: Theme.Dimensions.iconSize)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : .secondary)

                Text("All Workloads")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, Theme.Dimensions.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarItem(for kind: ResourceKind) -> some View {
        let isSelected = appState.selectedResourceKind == kind && !appState.showDashboard && !appState.showUnifiedWorkloads
        let isHovered = hoveredKind == kind

        return Button {
            appState.selectedResourceKind = kind
            appState.selectedResourceID = nil
            appState.isDetailPanelOpen = false
            appState.showDashboard = false
            appState.showUnifiedWorkloads = false
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: kind.icon)
                    .frame(width: Theme.Dimensions.iconSize)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : .secondary)

                Text(kind.pluralName)
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, Theme.Dimensions.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(
                        isSelected
                            ? Theme.Colors.accent.opacity(0.1)
                            : isHovered
                                ? Theme.Colors.hoverBackground
                                : .clear
                    )
            )
            .animation(Theme.Animations.hoverTransition, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredKind = hovering ? kind : nil
        }
    }
}
