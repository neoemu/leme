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
            case .resource:
                resourceContent
                    .transition(.opacity)
                    .animation(Theme.Animations.contentTransition, value: appState.selectedResourceKind)
            case .customResource(let target):
                SelectedCustomResourceListView(target: target)
                    .id(target.id)
                    .transition(.opacity)
            case .helmReleases:
                HelmReleaseListView()
                    .transition(.opacity)
            case .problems:
                ProblemsView()
                    .transition(.opacity)
            case .placeholder(let page):
                SidebarPlaceholderView(page: page)
                    .transition(.opacity)
            case nil:
                EmptyStateView(
                    icon: "shippingbox",
                    title: "Select a Resource",
                    message: "Choose a section from the sidebar to load resources."
                )
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
            NamespaceListView()
        // Network
        case .service:
            ServiceListView()
        case .ingress:
            IngressListView()
        case .endpoint:
            EndpointListView()
        case .horizontalPodAutoscaler:
            HorizontalPodAutoscalerListView()
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
        case .limitRange:
            LimitRangeListView()
        case .podDisruptionBudget:
            PodDisruptionBudgetListView()
        case .resourceQuota:
            ResourceQuotaListView()
        case .clusterRole:
            ClusterRoleListView()
        case .clusterRoleBinding:
            ClusterRoleBindingListView()
        case .roleBinding:
            RoleBindingListView()
        }
    }
}

private struct SidebarPlaceholderView: View {
    let page: SidebarPlaceholder

    private var metadata: (icon: String, title: String, message: String, secondary: String?) {
        switch page {
        case .moreResources:
            return (
                "square.grid.3x3",
                "More Resources",
                "Select a resource from the expanded More Resources section.",
                "Custom resources are grouped by API group."
            )
        }
    }

    var body: some View {
        EmptyStateView(
            icon: metadata.icon,
            title: metadata.title,
            message: metadata.message,
            secondaryMessage: metadata.secondary
        )
    }
}

private struct NamespacedResourceTableView<R: KubernetesAPIResource & NamespacedResource & ListableResource & ReadableResource>: View where R.List.Item == R {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    let resourceType: R.Type
    let kind: ResourceKind
    let emptyStateTitle: String
    let emptyStateMessage: String

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 140, sortField: .namespace),
        ResourceTableColumn(title: "Status", key: "status", width: 120, sortField: .status),
        ResourceTableColumn(title: "Age", key: "age", width: 70, sortField: .age),
    ]

    var body: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    do {
                        let yaml = try await viewModel.fetchResourceYAML(
                            kind: kind,
                            name: resource.name,
                            namespace: resource.namespace,
                            client: client
                        )
                        appState.showYAMLEditor(resourceID: resource.id, title: "YAML - \(resource.name)", yaml: yaml)
                    } catch {
                        appState.showYAMLEditor(
                            resourceID: resource.id,
                            title: "YAML - \(resource.name)",
                            yaml: "# Error loading YAML: \(error.localizedDescription)"
                        )
                    }
                }
            },
            onDelete: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.deleteResource(kind: kind, name: resource.name, namespace: resource.namespace, client: client)
                }
            },
            onDownloadYAML: { resource in
                Task {
                    guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                    await viewModel.downloadResourceYAML(kind: kind, name: resource.name, namespace: resource.namespace, client: client)
                }
            }
        )
        .overlay {
            if !viewModel.isLoading && viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: kind.icon,
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
            }
        }
        .task { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            resourceType,
            kind: kind,
            client: client,
            namespace: appState.selectedNamespace
        ) { resource in
            let namespace = resource.metadata?.namespace
            let name = resource.name ?? ""
            return ResourceItem(
                id: "\(namespace ?? "")/\(name)",
                name: name,
                namespace: namespace,
                status: "Active",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: kind
            )
        }
    }
}

private struct HorizontalPodAutoscalerListView: View {
    var body: some View {
        NamespacedResourceTableView(
            resourceType: autoscaling.v2.HorizontalPodAutoscaler.self,
            kind: .horizontalPodAutoscaler,
            emptyStateTitle: "No Horizontal Pod Autoscalers",
            emptyStateMessage: "No HPAs found in the current namespace."
        )
    }
}

private struct LimitRangeListView: View {
    var body: some View {
        NamespacedResourceTableView(
            resourceType: core.v1.LimitRange.self,
            kind: .limitRange,
            emptyStateTitle: "No Limit Ranges",
            emptyStateMessage: "No limit ranges found in the current namespace."
        )
    }
}

private struct PodDisruptionBudgetListView: View {
    var body: some View {
        NamespacedResourceTableView(
            resourceType: policy.v1.PodDisruptionBudget.self,
            kind: .podDisruptionBudget,
            emptyStateTitle: "No Pod Disruption Budgets",
            emptyStateMessage: "No pod disruption budgets found in the current namespace."
        )
    }
}

private struct ResourceQuotaListView: View {
    var body: some View {
        NamespacedResourceTableView(
            resourceType: core.v1.ResourceQuota.self,
            kind: .resourceQuota,
            emptyStateTitle: "No Resource Quotas",
            emptyStateMessage: "No resource quotas found in the current namespace."
        )
    }
}

private struct SelectedCustomResourceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    let target: CustomResourceNavigationTarget

    @State private var viewModel = ResourceListViewModel()

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 160, sortField: .namespace),
        ResourceTableColumn(title: "Status", key: "status", width: 140, sortField: .status),
        ResourceTableColumn(title: "Age", key: "age", width: 80, sortField: .age),
    ]

    private var definition: CustomResourceDefinitionInfo {
        target.definitionInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            table
        }
        .task(id: target.id) { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: target.id) { _, _ in
            appState.selectResource(nil)
            viewModel.searchText = ""
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text(definition.kind)
                .font(Theme.Fonts.title)

            Text(definition.group)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .fill(Color.secondary.opacity(0.12))
                )

            Spacer()

            Text("\(viewModel.filteredResources.count) items")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Button {
                Task { await loadData() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.padding)
    }

    private var table: some View {
        ResourceTableView(
            columns: columns,
            viewModel: viewModel,
            onViewYAML: { resource in
                Task { await openYAML(resource) }
            },
            onDelete: { resource in
                Task { await deleteResource(resource) }
            },
            deleteConfirmationMessageBuilder: { resource in
                let namespace = resource.namespace ?? appState.selectedNamespace ?? "cluster-scoped"
                return "Resource: \(definition.kind)\nNamespace: \(namespace)\nName: \(resource.name)\n\nThis action cannot be undone."
            }
        )
    }

    private func loadData() async {
        viewModel.isLoading = true
        viewModel.errorMessage = nil
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                viewModel.isLoading = false
                return
            }

            let service = KubernetesService(client: client)
            let customResources = try await service.listCustomResources(
                definition: definition,
                namespace: definition.isNamespaced ? appState.selectedNamespace : nil,
                context: appState.activeCluster?.contextName
            )
            viewModel.resources = customResources.map(resourceItem(from:))
        } catch {
            viewModel.resources = []
            viewModel.errorMessage = error.localizedDescription
        }
        viewModel.isLoading = false
    }

    private func resourceID(name: String, namespace: String?) -> String {
        if let namespace, !namespace.isEmpty {
            return "\(namespace)/\(name)"
        }
        return name
    }

    private func resourceItem(from item: CustomResourceItem) -> ResourceItem {
        // `ResourceItem.kind` is required by shared table/actions; custom resources use their own detail flow.
        ResourceItem(
            id: resourceID(name: item.name, namespace: item.namespace),
            name: item.name,
            namespace: item.namespace,
            status: item.status,
            age: item.age,
            labels: [:],
            annotations: [:],
            kind: .endpoint
        )
    }

    private func openYAML(_ resource: ResourceItem) async {
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                return
            }
            let service = KubernetesService(client: client)
            let yaml = try await service.getCustomResourceYAML(
                definition: definition,
                name: resource.name,
                namespace: resource.namespace,
                context: appState.activeCluster?.contextName
            )
            appState.showYAMLEditor(resourceID: resource.id, title: "YAML - \(resource.name)", yaml: yaml)
        } catch {
            viewModel.operationState = .error("Failed to open YAML: \(error.localizedDescription)")
        }
    }

    private func deleteResource(_ resource: ResourceItem) async {
        viewModel.operationState = .running("Deleting \(definition.kind) \(resource.name)…")
        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                return
            }
            let service = KubernetesService(client: client)
            try await service.deleteCustomResource(
                definition: definition,
                name: resource.name,
                namespace: resource.namespace,
                context: appState.activeCluster?.contextName
            )
            viewModel.operationState = .success("Deleted \(definition.kind) \(resource.name)")
            await loadData()
        } catch {
            viewModel.operationState = .error("Delete failed: \(error.localizedDescription)")
        }
    }
}
