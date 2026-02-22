import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ContentAreaView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.contentBackground)
    }

    @ViewBuilder
    private var mainContent: some View {
        if appState.activeCluster != nil {
            switch appState.sidebarSelection {
            case .dashboard:
                ClusterDashboardView()
                    .transition(.opacity)
            case .unifiedWorkloads:
                UnifiedWorkloadsView()
                    .transition(.opacity)
            case .resource:
                resourceContent
                    .transition(.opacity)
                    .animation(Theme.Animations.contentTransition, value: appState.selectedResourceKind)
            case nil:
                ClusterDashboardView()
                    .transition(.opacity)
            }
        } else {
            EmptyStateView(
                icon: "server.rack",
                title: "No Cluster Selected",
                message: "Select a cluster from the sidebar to get started.",
                secondaryMessage: "Add a cluster by configuring your kubeconfig file."
            )
        }
    }

    @ViewBuilder
    private var resourceContent: some View {
        VStack(spacing: 0) {
            resourceHeader
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
}
