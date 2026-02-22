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
                    .frame(
                        minWidth: Theme.Dimensions.detailPanelMinWidth,
                        idealWidth: Theme.Dimensions.detailPanelIdealWidth,
                        maxWidth: Theme.Dimensions.detailPanelMaxWidth
                    )
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
            if appState.showDashboard {
                ClusterDashboardView()
                    .transition(.opacity)
            } else if appState.showUnifiedWorkloads {
                UnifiedWorkloadsView()
                    .transition(.opacity)
            } else {
                resourceContent
                    .transition(.opacity)
                    .animation(Theme.Animations.contentTransition, value: appState.selectedResourceKind)
            }
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
        case .replicaSet:
            ReplicaSetListView()
        case .networkPolicy:
            NetworkPolicyListView()
        case .clusterRole:
            ClusterRoleListView()
        case .clusterRoleBinding:
            ClusterRoleBindingListView()
        case .roleBinding:
            RoleBindingListView()
        }
    }

    // MARK: - Detail Loading

    @MainActor
    private func loadDetail(resourceID: String) async {
        let parts = resourceID.split(separator: "/", maxSplits: 1)
        let namespace: String?
        let name: String

        if appState.selectedResourceKind.isNamespaced {
            guard parts.count == 2 else { return }
            namespace = String(parts[0])
            name = String(parts[1])
        } else {
            // Cluster-scoped resources use just the name as ID
            name = parts.count == 2 ? String(parts[1]) : String(parts[0])
            namespace = nil
        }

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
            let detail = ResourceDetailViewModel(client: client)
            detailViewModel = detail

            switch appState.selectedResourceKind {
            // Workloads
            case .pod:
                await detail.loadPodDetail(name: name, namespace: namespace ?? "default")
            case .deployment:
                await detail.loadDeploymentDetail(name: name, namespace: namespace ?? "default")
            case .statefulSet:
                await detail.loadDetail(apps.v1.StatefulSet.self, name: name, namespace: namespace ?? "default")
            case .daemonSet:
                await detail.loadDetail(apps.v1.DaemonSet.self, name: name, namespace: namespace ?? "default")
            case .job:
                await detail.loadDetail(batch.v1.Job.self, name: name, namespace: namespace ?? "default")
            case .cronJob:
                await detail.loadDetail(batch.v1.CronJob.self, name: name, namespace: namespace ?? "default")
            case .replicaSet:
                await detail.loadDetail(apps.v1.ReplicaSet.self, name: name, namespace: namespace ?? "default")

            // Network
            case .service:
                await detail.loadDetail(core.v1.Service.self, name: name, namespace: namespace ?? "default")
            case .ingress:
                await detail.loadDetail(networking.v1.Ingress.self, name: name, namespace: namespace ?? "default")
            case .endpoint:
                await detail.loadDetail(core.v1.Endpoints.self, name: name, namespace: namespace ?? "default")
            case .networkPolicy:
                await detail.loadDetail(networking.v1.NetworkPolicy.self, name: name, namespace: namespace ?? "default")

            // Configuration
            case .configMap:
                await detail.loadDetail(core.v1.ConfigMap.self, name: name, namespace: namespace ?? "default")
            case .secret:
                await detail.loadDetail(core.v1.Secret.self, name: name, namespace: namespace ?? "default")

            // Storage (namespaced)
            case .persistentVolumeClaim:
                await detail.loadDetail(core.v1.PersistentVolumeClaim.self, name: name, namespace: namespace ?? "default")

            // Access Control (namespaced)
            case .serviceAccount:
                await detail.loadDetail(core.v1.ServiceAccount.self, name: name, namespace: namespace ?? "default")
            case .role:
                await detail.loadDetail(rbac.v1.Role.self, name: name, namespace: namespace ?? "default")
            case .roleBinding:
                await detail.loadDetail(rbac.v1.RoleBinding.self, name: name, namespace: namespace ?? "default")

            // Events
            case .event:
                await detail.loadDetail(core.v1.Event.self, name: name, namespace: namespace ?? "default")

            // Cluster-scoped resources
            case .node:
                await detail.loadClusterScopedDetail(core.v1.Node.self, name: name)
            case .persistentVolume:
                await detail.loadClusterScopedDetail(core.v1.PersistentVolume.self, name: name)
            case .storageClass:
                await detail.loadClusterScopedDetail(storage.v1.StorageClass.self, name: name)
            case .clusterRole:
                await detail.loadClusterScopedDetail(rbac.v1.ClusterRole.self, name: name)
            case .clusterRoleBinding:
                await detail.loadClusterScopedDetail(rbac.v1.ClusterRoleBinding.self, name: name)

            // Namespace (no detail view yet)
            case .namespace:
                break
            }
        } catch {
            // Detail loading error handled by the detail view model
        }
    }
}
