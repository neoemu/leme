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
        case .projectsNamespaces:
            return (
                "square.split.2x1",
                "Projects/Namespaces",
                "Project-style namespace management is not available yet.",
                "Use the namespace filter in the sidebar to scope namespaced resources."
            )
        case .clusterMembers:
            return (
                "person.3",
                "Cluster and Project Members",
                "Member management is not implemented yet.",
                "RBAC resources are available under More Resources."
            )
        case .tools:
            return (
                "wrench.and.screwdriver",
                "Tools",
                "Built-in tools are not implemented yet.",
                "Use the command palette and bottom panel for logs and terminal workflows."
            )
        case .charts:
            return ("shippingbox", "Charts", "Chart catalog is not implemented yet.", nil)
        case .installedApps:
            return ("square.stack.3d.up", "Installed Apps", "Helm app management is not implemented yet.", nil)
        case .repositories:
            return ("books.vertical", "Repositories", "Repository management is not implemented yet.", nil)
        case .recentOperations:
            return ("clock.arrow.circlepath", "Recent Operations", "Operation history is not implemented yet.", nil)
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

private struct NamespacedResourceTableView<R: KubernetesAPIResource & NamespacedResource & ListableResource>: View where R.List.Item == R {
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

private struct CustomResourcesView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var definitions: [CustomResourceDefinitionInfo] = []
    @State private var selectedDefinitionID: String?
    @State private var resources: [CustomResourceItem] = []
    @State private var selectedResourceID: String?
    @State private var definitionSearchText: String = ""
    @State private var isLoadingDefinitions = false
    @State private var isLoadingResources = false
    @State private var errorMessage: String?
    @State private var operationMessage: String?
    @State private var operationIsError = false
    @State private var resourceToDelete: CustomResourceItem?
    @State private var showDeleteConfirmation = false
    @State private var expandedGroups: Set<String> = []
    @State private var knownGroups: Set<String> = []
    @State private var groupsWithResources: Set<String> = []

    private var selectedDefinition: CustomResourceDefinitionInfo? {
        guard let selectedDefinitionID else { return nil }
        return definitions.first { $0.id == selectedDefinitionID }
    }

    private var filteredDefinitions: [CustomResourceDefinitionInfo] {
        let query = definitionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return definitions }
        let normalized = query.lowercased()
        return definitions.filter { definition in
            definition.kind.lowercased().contains(normalized)
                || definition.group.lowercased().contains(normalized)
                || definition.name.lowercased().contains(normalized)
                || definition.plural.lowercased().contains(normalized)
        }
    }

    private var groupedDefinitionKeys: [String] {
        let keys = Set(filteredDefinitions.map(\.group))
        return keys.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var visibleGroupedDefinitionKeys: [String] {
        if groupsWithResources.isEmpty {
            return groupedDefinitionKeys
        }
        return groupedDefinitionKeys.filter { groupsWithResources.contains($0) }
    }

    private func definitionsForGroup(_ group: String, from source: [CustomResourceDefinitionInfo]? = nil) -> [CustomResourceDefinitionInfo] {
        (source ?? filteredDefinitions)
            .filter { $0.group == group }
            .sorted { lhs, rhs in
                lhs.kind.localizedCaseInsensitiveCompare(rhs.kind) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            splitContent
        }
        .task {
            await reloadAll()
        }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await reloadAll() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await startGroupPresenceRefreshForCurrentDefinitions()
                await reloadResourcesForSelection()
            }
        }
        .onChange(of: selectedDefinitionID) { _, _ in
            Task { await reloadResourcesForSelection() }
        }
        .onChange(of: definitionSearchText) { _, newValue in
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                expandedGroups = Set(groupedDefinitionKeys)
            }
        }
        .confirmationDialog(
            "Delete \(resourceToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let resource = resourceToDelete else { return }
                resourceToDelete = nil
                Task {
                    await deleteResource(resource)
                }
            }
            Button("Cancel", role: .cancel) {
                resourceToDelete = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Custom Resources")
                .font(Theme.Fonts.title)

            Spacer()

            if isLoadingDefinitions || isLoadingResources {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await reloadAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(Theme.Fonts.sidebarItem)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.padding)
    }

    private var splitContent: some View {
        HSplitView {
            definitionsPane
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
            resourcesPane
                .frame(minWidth: 420)
        }
    }

    private var definitionsPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.secondaryText)
                TextField("Search CRDs", text: $definitionSearchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sidebarItem)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.smallSpacing)

            Divider()

            if isLoadingDefinitions && definitions.isEmpty {
                VStack(spacing: Theme.Dimensions.spacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading CRDs...")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredDefinitions.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No CRDs Found",
                    message: definitionSearchText.isEmpty
                        ? "No custom resource definitions are available in this cluster."
                        : "No custom resources match '\(definitionSearchText)'."
                )
            } else if visibleGroupedDefinitionKeys.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No Groups With Resources",
                    message: appState.selectedNamespace == nil
                        ? "No custom resources with instances were found in this cluster."
                        : "No custom resources with instances were found in namespace '\(appState.selectedNamespace ?? "")'."
                )
            } else {
                List(selection: $selectedDefinitionID) {
                    ForEach(visibleGroupedDefinitionKeys, id: \.self) { group in
                        let defsInGroup = definitionsForGroup(group)
                        DisclosureGroup(
                            isExpanded: isGroupExpanded(group)
                        ) {
                            ForEach(defsInGroup) { definition in
                                definitionRow(definition)
                                    .tag(definition.id)
                            }
                        } label: {
                            HStack(spacing: Theme.Dimensions.smallSpacing) {
                                Text(group)
                                    .font(Theme.Fonts.sidebarHeader)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .lineLimit(1)
                                Text("\(defsInGroup.count)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func isGroupExpanded(_ group: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { newValue in
                if newValue {
                    expandedGroups.insert(group)
                } else {
                    expandedGroups.remove(group)
                }
            }
        )
    }

    private func definitionRow(_ definition: CustomResourceDefinitionInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Text(definition.plural)
                    .font(Theme.Fonts.sidebarItem)
                    .lineLimit(1)
                Text(definition.version)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.cardBackground)
                    )
                Text(definition.scope == "Namespaced" ? "NS" : "Cluster")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.cardBackground)
                    )
            }

            Text(definition.kind)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var resourcesPane: some View {
        VStack(spacing: 0) {
            resourcesHeader

            if let operationMessage {
                HStack(spacing: Theme.Dimensions.smallSpacing) {
                    Image(systemName: operationIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(operationIsError ? Theme.Colors.failed : Theme.Colors.running)
                    Text(operationMessage)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(operationIsError ? Theme.Colors.failed : Theme.Colors.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.smallSpacing)
                .background(operationIsError ? Theme.Colors.errorBackground : Theme.Colors.successBackground)
                Divider()
            }

            if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Failed to Load Custom Resources",
                    message: errorMessage
                )
            } else if let _ = selectedDefinition {
                resourcesTable
            } else {
                EmptyStateView(
                    icon: "sidebar.left",
                    title: "Select A Definition",
                    message: "Pick a custom resource definition on the left to list instances."
                )
            }
        }
    }

    private var resourcesHeader: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            if let selectedDefinition {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedDefinition.group) / \(selectedDefinition.plural)")
                        .font(Theme.Fonts.subtitle)
                    Text("Kind: \(selectedDefinition.kind) • Version: \(selectedDefinition.version)")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("Resources")
                    .font(Theme.Fonts.subtitle)
            }

            Spacer()

            Text("\(resources.count) items")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.spacing)
        .background(Theme.Colors.cardBackground)
    }

    private var resourcesTable: some View {
        Table(resources, selection: $selectedResourceID) {
            TableColumn("Name") { item in
                Text(item.name)
                    .font(Theme.Fonts.monoSmall)
                    .contextMenu {
                        Button {
                            Task { await openYAML(item) }
                        } label: {
                            Label("Edit YAML", systemImage: "doc.plaintext")
                        }

                        Button(role: .destructive) {
                            resourceToDelete = item
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .width(min: 120, ideal: 220)

            TableColumn("Namespace") { item in
                Text(item.namespace ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Status") { item in
                StatusBadge(status: item.status)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Age") { item in
                if let age = item.age {
                    AgeLabel(date: age)
                } else {
                    Text("-")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .width(min: 60, ideal: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var deleteConfirmationMessage: String {
        guard let resource = resourceToDelete, let selectedDefinition else {
            return "This action cannot be undone."
        }

        let namespace = resource.namespace ?? "cluster-scoped"
        return "Resource: \(selectedDefinition.kind)\nNamespace: \(namespace)\nName: \(resource.name)\n\nThis action cannot be undone."
    }

    @MainActor
    private func reloadAll() async {
        await reloadDefinitions()
        await reloadResourcesForSelection()
    }

    @MainActor
    private func reloadDefinitions() async {
        isLoadingDefinitions = true
        errorMessage = nil

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                isLoadingDefinitions = false
                return
            }

            let service = KubernetesService(client: client)
            let loaded = try await service.listCustomResourceDefinitions(context: appState.activeCluster?.contextName)
            definitions = loaded

            // Show groups immediately; refine to "only groups with resources" right after probing.
            groupsWithResources = Set(loaded.map(\.group))

            let allGroups = Set(loaded.map(\.group))
            expandedGroups = expandedGroups.intersection(allGroups)
            knownGroups = allGroups

            await startGroupPresenceRefresh(definitions: loaded, client: client)

            if let selectedDefinitionID,
               let selectedDefinition = loaded.first(where: { $0.id == selectedDefinitionID }),
               !groupsWithResources.contains(selectedDefinition.group) {
                self.selectedDefinitionID = nil
            }

            if let selectedDefinitionID,
               !loaded.contains(where: { $0.id == selectedDefinitionID }) {
                self.selectedDefinitionID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            definitions = []
            selectedDefinitionID = nil
            resources = []
            expandedGroups = []
            knownGroups = []
            groupsWithResources = []
        }

        isLoadingDefinitions = false
    }

    @MainActor
    private func startGroupPresenceRefreshForCurrentDefinitions() async {
        guard !definitions.isEmpty else {
            groupsWithResources = []
            return
        }
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }
        await startGroupPresenceRefresh(definitions: definitions, client: client)
    }

    @MainActor
    private func startGroupPresenceRefresh(definitions: [CustomResourceDefinitionInfo], client: KubernetesClient) async {
        let snapshotNamespace = appState.selectedNamespace
        let snapshotContext = appState.activeCluster?.contextName
        let snapshotDefinitions = definitions

        await refreshGroupPresence(
            definitions: snapshotDefinitions,
            client: client,
            namespace: snapshotNamespace,
            context: snapshotContext
        )
    }

    @MainActor
    private func refreshGroupPresence(
        definitions: [CustomResourceDefinitionInfo],
        client: KubernetesClient,
        namespace: String?,
        context: String?
    ) async {
        let service = KubernetesService(client: client)
        var visibleGroups: Set<String> = []
        let groups = Set(definitions.map(\.group))

        for group in groups {
            let defs = definitionsForGroup(group, from: definitions)
            var groupHasResources = false

            for definition in defs {
                do {
                    let hasItems = try await service.hasAnyCustomResourceInstances(
                        definition: definition,
                        namespace: namespace,
                        context: context
                    )
                    if hasItems {
                        groupHasResources = true
                        break
                    }
                } catch {
                    // If probing fails (RBAC/connectivity), keep the group visible.
                    groupHasResources = true
                    break
                }
            }

            if groupHasResources {
                visibleGroups.insert(group)
            }
        }

        // Drop stale background results if user switched cluster/namespace while probing.
        guard namespace == appState.selectedNamespace,
              context == appState.activeCluster?.contextName else {
            return
        }

        groupsWithResources = visibleGroups
        expandedGroups = expandedGroups.intersection(visibleGroups)
        if let selectedDefinition,
           !groupsWithResources.contains(selectedDefinition.group) {
            selectedDefinitionID = nil
        }
    }

    @MainActor
    private func reloadResourcesForSelection() async {
        guard let definition = selectedDefinition else {
            resources = []
            return
        }

        isLoadingResources = true
        errorMessage = nil

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                isLoadingResources = false
                return
            }

            let service = KubernetesService(client: client)
            resources = try await service.listCustomResources(
                definition: definition,
                namespace: appState.selectedNamespace,
                context: appState.activeCluster?.contextName
            )
        } catch {
            errorMessage = error.localizedDescription
            resources = []
        }

        isLoadingResources = false
    }

    @MainActor
    private func openYAML(_ item: CustomResourceItem) async {
        guard let definition = selectedDefinition else { return }

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                return
            }

            let service = KubernetesService(client: client)
            let yaml = try await service.getCustomResourceYAML(
                definition: definition,
                name: item.name,
                namespace: item.namespace,
                context: appState.activeCluster?.contextName
            )

            appState.showYAMLEditor(
                resourceID: nil,
                title: "YAML - \(item.name)",
                yaml: yaml
            )
            operationMessage = "Loaded YAML for \(item.name)"
            operationIsError = false
        } catch {
            operationMessage = "Failed to load YAML: \(error.localizedDescription)"
            operationIsError = true
        }
    }

    @MainActor
    private func deleteResource(_ item: CustomResourceItem) async {
        guard let definition = selectedDefinition else { return }

        do {
            guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                return
            }

            let service = KubernetesService(client: client)
            try await service.deleteCustomResource(
                definition: definition,
                name: item.name,
                namespace: item.namespace,
                context: appState.activeCluster?.contextName
            )

            resources.removeAll { $0.id == item.id }
            operationMessage = "Deleted \(item.name)"
            operationIsError = false
        } catch {
            operationMessage = "Delete failed: \(error.localizedDescription)"
            operationIsError = true
        }
    }
}
