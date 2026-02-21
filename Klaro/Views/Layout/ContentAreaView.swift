import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ContentAreaView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var detailViewModel: ResourceDetailViewModel?

    var body: some View {
        HSplitView {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.isDetailPanelOpen, let detailVM = detailViewModel {
                ResourceDetailPanel(viewModel: detailVM)
                    .frame(width: Theme.Dimensions.detailPanelWidth)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isDetailPanelOpen)
        .background(Theme.Colors.contentBackground)
        .onChange(of: appState.selectedResourceID) { _, newValue in
            if let resourceID = newValue {
                Task {
                    await loadDetail(resourceID: resourceID)
                }
            } else {
                detailViewModel = nil
            }
        }
        .onChange(of: appState.isDetailPanelOpen) { _, isOpen in
            if !isOpen {
                detailViewModel = nil
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if appState.activeCluster != nil {
            resourceContent
                .transition(.opacity)
                .animation(Theme.Animations.contentTransition, value: appState.selectedResourceKind)
        } else {
            EmptyStateView(
                icon: "server.rack",
                title: "No Cluster Selected",
                message: "Select a cluster from the hotbar to get started.",
                secondaryMessage: "Add a cluster by configuring your kubeconfig file."
            )
        }
    }

    @ViewBuilder
    private var resourceContent: some View {
        VStack(spacing: 0) {
            // Consistent header bar
            resourceHeader
            // Resource list view
            resourceListView
        }
    }

    private var resourceHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: appState.selectedResourceKind.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.accent)

                Text(appState.selectedResourceKind.pluralName)
                    .font(Theme.Fonts.title)

                Spacer()

                if let cluster = appState.activeCluster {
                    if cluster.status == .error, let errorMsg = cluster.errorMessage {
                        HStack(spacing: Theme.Dimensions.smallSpacing) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.failed)
                            Text(errorMsg)
                                .font(Theme.Fonts.errorMessage)
                                .foregroundStyle(Theme.Colors.failed)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                                .fill(Theme.Colors.errorBackground)
                        )
                    }
                }

                if appState.selectedResourceKind.isNamespaced,
                   let ns = appState.selectedNamespace {
                    Text(ns)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.top, Theme.Dimensions.padding)

            Divider()
                .padding(.top, Theme.Dimensions.spacing)
        }
    }

    @ViewBuilder
    private var resourceListView: some View {
        switch appState.selectedResourceKind {
        // Workloads
        case .pod:
            PodListView()
        case .deployment:
            DeploymentListView()
        case .statefulSet:
            StatefulSetListView()
        case .daemonSet:
            DaemonSetListView()
        case .job:
            JobListView()
        case .cronJob:
            CronJobListView()
        // Cluster
        case .node:
            NodeListView()
        case .namespace:
            EmptyStateView(
                icon: ResourceKind.namespace.icon,
                title: "Namespaces",
                message: "Namespace management is not yet available.",
                secondaryMessage: "Use the namespace filter in the sidebar to switch namespaces."
            )
        // Network
        case .service:
            ServiceListView()
        case .ingress:
            IngressListView()
        case .endpoint:
            EndpointListView()
        // Configuration
        case .configMap:
            ConfigMapListView()
        case .secret:
            SecretListView()
        // Storage
        case .persistentVolumeClaim:
            PVCListView()
        case .persistentVolume:
            PVListView()
        case .storageClass:
            StorageClassListView()
        // Access Control
        case .serviceAccount:
            ServiceAccountListView()
        case .role:
            RoleListView()
        // Events
        case .event:
            EventListView()
        // Placeholder for remaining resource kinds
        case .replicaSet, .networkPolicy, .clusterRole, .clusterRoleBinding, .roleBinding:
            EmptyStateView(
                icon: appState.selectedResourceKind.icon,
                title: appState.selectedResourceKind.pluralName,
                message: "This resource view is coming soon.",
                secondaryMessage: "Support for \(appState.selectedResourceKind.pluralName) will be added in a future update."
            )
        }
    }

    // MARK: - Detail Loading

    @MainActor
    private func loadDetail(resourceID: String) async {
        let parts = resourceID.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return }
        let namespace = String(parts[0])
        let name = String(parts[1])

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            let detail = ResourceDetailViewModel(client: client)
            detailViewModel = detail

            switch appState.selectedResourceKind {
            case .pod:
                await detail.loadPodDetail(name: name, namespace: namespace)
            case .deployment:
                await detail.loadDeploymentDetail(name: name, namespace: namespace)
            case .statefulSet:
                await detail.loadDetail(apps.v1.StatefulSet.self, name: name, namespace: namespace)
            case .daemonSet:
                await detail.loadDetail(apps.v1.DaemonSet.self, name: name, namespace: namespace)
            case .job:
                await detail.loadDetail(batch.v1.Job.self, name: name, namespace: namespace)
            case .cronJob:
                await detail.loadDetail(batch.v1.CronJob.self, name: name, namespace: namespace)
            default:
                break
            }
        } catch {
            // Detail loading error handled by the detail view model
        }
    }
}
