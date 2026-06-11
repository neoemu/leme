import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct InspectorDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var detailViewModel: ResourceDetailViewModel?
    @State private var loadFailure: String?

    var body: some View {
        Group {
            if let detailVM = detailViewModel {
                ResourceDetailPanel(viewModel: detailVM)
            } else if let loadFailure {
                ContentUnavailableView(
                    "Couldn't Load Details",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadFailure)
                )
            } else if appState.selectedResourceID != nil {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Resource Selected",
                    systemImage: "sidebar.trailing",
                    description: Text("Select a resource from the list to view details.")
                )
            }
        }
        .task(id: appState.selectedResourceID) {
            loadFailure = nil
            if let resourceID = appState.selectedResourceID {
                await loadDetail(resourceID: resourceID)
            } else {
                detailViewModel = nil
            }
        }
    }

    // MARK: - Detail Loading

    @MainActor
    private func loadDetail(resourceID: String) async {
        if case .customResource(let target) = appState.sidebarSelection {
            let parts = resourceID.split(separator: "/", maxSplits: 1)
            let name: String
            let namespace: String?

            if target.definitionInfo.isNamespaced {
                if parts.count == 2 {
                    namespace = String(parts[0])
                    name = String(parts[1])
                } else {
                    namespace = appState.selectedNamespace
                    name = String(parts[0])
                }
            } else {
                name = parts.count == 2 ? String(parts[1]) : String(parts[0])
                namespace = nil
            }

            do {
                guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                    loadFailure = "No active cluster connection."
                    return
                }
                let detail = ResourceDetailViewModel(client: client, contextName: appState.activeCluster?.contextName)
                detailViewModel = detail
                await detail.loadCustomResourceDetail(
                    definition: target.definitionInfo,
                    name: name,
                    namespace: namespace,
                    context: appState.activeCluster?.contextName
                )
            } catch {
                loadFailure = error.localizedDescription
            }
            return
        }

        let parts = resourceID.split(separator: "/", maxSplits: 1)
        let namespace: String?
        let name: String

        if appState.selectedResourceKind.isNamespaced {
            guard parts.count == 2 else {
                loadFailure = "Unexpected resource identifier '\(resourceID)'."
                return
            }
            namespace = String(parts[0])
            name = String(parts[1])
        } else {
            name = parts.count == 2 ? String(parts[1]) : String(parts[0])
            namespace = nil
        }

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                loadFailure = "No active cluster connection."
                return
            }
            let detail = ResourceDetailViewModel(client: client, contextName: appState.activeCluster?.contextName)
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
            case .horizontalPodAutoscaler:
                await detail.loadDetail(autoscaling.v2.HorizontalPodAutoscaler.self, name: name, namespace: namespace ?? "default")
            case .networkPolicy:
                await detail.loadDetail(networking.v1.NetworkPolicy.self, name: name, namespace: namespace ?? "default")
            case .limitRange:
                await detail.loadDetail(core.v1.LimitRange.self, name: name, namespace: namespace ?? "default")
            case .podDisruptionBudget:
                await detail.loadDetail(policy.v1.PodDisruptionBudget.self, name: name, namespace: namespace ?? "default")
            case .resourceQuota:
                await detail.loadDetail(core.v1.ResourceQuota.self, name: name, namespace: namespace ?? "default")

            // Configuration
            case .configMap:
                await detail.loadDetail(core.v1.ConfigMap.self, name: name, namespace: namespace ?? "default")
            case .secret:
                await detail.loadSecretDetail(name: name, namespace: namespace ?? "default")

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
                await detail.loadEventDetail(name: name, namespace: namespace ?? "default")

            // Cluster-scoped resources
            case .node:
                await detail.loadNodeDetail(name: name)
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
