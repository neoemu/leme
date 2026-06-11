import SwiftUI
import SwiftkubeModel

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var expandedSections: Set<String> = SidebarView.defaultExpandedSections
    @State private var expandedCRDGroups: Set<String> = []
    @State private var kindCounts: [ResourceKind: Int] = [:]
    @State private var crdDefinitionsByGroup: [String: [CustomResourceDefinitionInfo]] = [:]
    @State private var crdCounts: [String: Int] = [:]
    @State private var isRefreshing = false
    @State private var isManualRefreshInProgress = false
    @State private var refreshTask: Task<Void, Never>?

    private static let expandedSectionsDefaultsKey = "sidebar.expanded.sections.v2"
    private static let expandedCRDGroupsDefaultsKey = "sidebar.expanded.crd.groups.v2"
    private static let defaultExpandedSections: Set<String> = [
        "cluster",
        "workloads",
        "apps",
        "service-discovery",
        "storage",
        "policy",
        "more-resources",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ClusterSwitcherView()
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.spacing)

            Divider()
                .overlay(Theme.Colors.sidebarMutedText.opacity(0.12))

            if appState.activeCluster != nil {
                NamespaceFilterView()
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.vertical, Theme.Dimensions.spacing)

                refreshBar
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.bottom, Theme.Dimensions.spacing)
            }

            ScrollView {
                VStack(spacing: 0) {
                    sidebarSection(title: "Cluster", id: "cluster") {
                        row(title: "Projects/Namespaces", icon: "square.split.2x1", selection: .placeholder(.projectsNamespaces))
                        row(title: ResourceKind.node.pluralName, icon: ResourceKind.node.icon, selection: .resource(.node), countKind: .node)
                        row(title: "Cluster and Project Members", icon: "person.3", selection: .placeholder(.clusterMembers))
                        row(title: ResourceKind.event.pluralName, icon: ResourceKind.event.icon, selection: .resource(.event), countKind: .event)
                        row(title: "Tools", icon: "wrench.and.screwdriver", selection: .placeholder(.tools))
                    }

                    sidebarSection(title: "Workloads", id: "workloads") {
                        row(title: ResourceKind.cronJob.pluralName, icon: ResourceKind.cronJob.icon, selection: .resource(.cronJob), countKind: .cronJob)
                        row(title: ResourceKind.daemonSet.pluralName, icon: ResourceKind.daemonSet.icon, selection: .resource(.daemonSet), countKind: .daemonSet)
                        row(title: ResourceKind.deployment.pluralName, icon: ResourceKind.deployment.icon, selection: .resource(.deployment), countKind: .deployment)
                        row(title: ResourceKind.job.pluralName, icon: ResourceKind.job.icon, selection: .resource(.job), countKind: .job)
                        row(title: ResourceKind.statefulSet.pluralName, icon: ResourceKind.statefulSet.icon, selection: .resource(.statefulSet), countKind: .statefulSet)
                        row(title: ResourceKind.pod.pluralName, icon: ResourceKind.pod.icon, selection: .resource(.pod), countKind: .pod)
                        row(title: ResourceKind.replicaSet.pluralName, icon: ResourceKind.replicaSet.icon, selection: .resource(.replicaSet), countKind: .replicaSet)
                    }

                    sidebarSection(title: "Apps", id: "apps") {
                        row(title: "Charts", icon: "shippingbox", selection: .placeholder(.charts))
                        row(title: "Installed Apps", icon: "square.stack.3d.up", selection: .helmReleases)
                        row(title: "Repositories", icon: "books.vertical", selection: .placeholder(.repositories))
                        row(title: "Recent Operations", icon: "clock.arrow.circlepath", selection: .placeholder(.recentOperations))
                    }

                    sidebarSection(title: "Service Discovery", id: "service-discovery") {
                        row(title: ResourceKind.horizontalPodAutoscaler.pluralName, icon: ResourceKind.horizontalPodAutoscaler.icon, selection: .resource(.horizontalPodAutoscaler), countKind: .horizontalPodAutoscaler)
                        row(title: ResourceKind.ingress.pluralName, icon: ResourceKind.ingress.icon, selection: .resource(.ingress), countKind: .ingress)
                        row(title: ResourceKind.service.pluralName, icon: ResourceKind.service.icon, selection: .resource(.service), countKind: .service)
                    }

                    sidebarSection(title: "Storage", id: "storage") {
                        row(title: ResourceKind.persistentVolume.pluralName, icon: ResourceKind.persistentVolume.icon, selection: .resource(.persistentVolume), countKind: .persistentVolume)
                        row(title: ResourceKind.storageClass.pluralName, icon: ResourceKind.storageClass.icon, selection: .resource(.storageClass), countKind: .storageClass)
                        row(title: ResourceKind.configMap.pluralName, icon: ResourceKind.configMap.icon, selection: .resource(.configMap), countKind: .configMap)
                        row(title: ResourceKind.persistentVolumeClaim.pluralName, icon: ResourceKind.persistentVolumeClaim.icon, selection: .resource(.persistentVolumeClaim), countKind: .persistentVolumeClaim)
                        row(title: ResourceKind.secret.pluralName, icon: ResourceKind.secret.icon, selection: .resource(.secret), countKind: .secret)
                    }

                    sidebarSection(title: "Policy", id: "policy") {
                        row(title: ResourceKind.limitRange.pluralName, icon: ResourceKind.limitRange.icon, selection: .resource(.limitRange), countKind: .limitRange)
                        row(title: ResourceKind.networkPolicy.pluralName, icon: ResourceKind.networkPolicy.icon, selection: .resource(.networkPolicy), countKind: .networkPolicy)
                        row(title: ResourceKind.podDisruptionBudget.pluralName, icon: ResourceKind.podDisruptionBudget.icon, selection: .resource(.podDisruptionBudget), countKind: .podDisruptionBudget)
                        row(title: ResourceKind.resourceQuota.pluralName, icon: ResourceKind.resourceQuota.icon, selection: .resource(.resourceQuota), countKind: .resourceQuota)
                    }

                    sidebarSection(title: "More Resources", id: "more-resources") {
                        row(title: ResourceKind.endpoint.pluralName, icon: ResourceKind.endpoint.icon, selection: .resource(.endpoint), countKind: .endpoint)
                        row(title: ResourceKind.namespace.pluralName, icon: ResourceKind.namespace.icon, selection: .resource(.namespace), countKind: .namespace)
                        row(title: ResourceKind.serviceAccount.pluralName, icon: ResourceKind.serviceAccount.icon, selection: .resource(.serviceAccount), countKind: .serviceAccount)
                        row(title: ResourceKind.role.pluralName, icon: ResourceKind.role.icon, selection: .resource(.role), countKind: .role)
                        row(title: ResourceKind.roleBinding.pluralName, icon: ResourceKind.roleBinding.icon, selection: .resource(.roleBinding), countKind: .roleBinding)
                        row(title: ResourceKind.clusterRole.pluralName, icon: ResourceKind.clusterRole.icon, selection: .resource(.clusterRole), countKind: .clusterRole)
                        row(title: ResourceKind.clusterRoleBinding.pluralName, icon: ResourceKind.clusterRoleBinding.icon, selection: .resource(.clusterRoleBinding), countKind: .clusterRoleBinding)

                        if !sortedCRDGroups.isEmpty {
                            Divider()
                                .overlay(Theme.Colors.sidebarMutedText.opacity(0.10))
                                .padding(.vertical, 4)

                            ForEach(sortedCRDGroups, id: \.key) { group, definitions in
                                crdGroup(title: group, definitions: definitions)
                            }
                        }
                    }
                }
                .padding(.top, Theme.Dimensions.smallSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .opacity(appState.activeCluster != nil ? 1.0 : 0.45)
            .allowsHitTesting(appState.activeCluster != nil)
        }
        .navigationTitle("Klaro")
        .foregroundStyle(Theme.Colors.sidebarText)
        .background(Theme.Colors.sidebarBackground)
        .onAppear {
            restoreExpandedState()
            startAutoRefreshLoop()
            Task { await refreshSidebarData() }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .onChange(of: appState.sidebarSelection) { _, _ in
            appState.selectedResourceID = nil
            appState.isDetailPanelOpen = false
            appState.closeYAMLEditor()
        }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await refreshSidebarData() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await refreshSidebarData() }
        }
        .onChange(of: expandedSections) { _, newValue in
            persistExpandedSections(newValue)
        }
        .onChange(of: expandedCRDGroups) { _, newValue in
            persistExpandedCRDGroups(newValue)
        }
    }

    private var sortedCRDGroups: [(key: String, value: [CustomResourceDefinitionInfo])] {
        crdDefinitionsByGroup
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }
    }

    private var refreshBar: some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            Text("Navigation")
                .font(Theme.Fonts.sidebarHeader)
                .foregroundStyle(Theme.Colors.sidebarMutedText)

            Spacer()

            if isManualRefreshInProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Colors.sidebarText)
            }

            Button {
                Task { await refreshSidebarData(showSpinner: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.sidebarMutedText)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Refresh sections and counts")
        }
        .padding(.horizontal, Theme.Dimensions.smallSpacing)
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        let isExpanded = expandedSections.contains(id)

        VStack(spacing: 0) {
            Button {
                toggleSection(id)
            } label: {
                HStack(spacing: Theme.Dimensions.spacing) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.sidebarText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.sidebarMutedText)
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isExpanded
                        ? Theme.Colors.sidebarExpandedHeaderBackground
                        : Color.clear
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                VStack(spacing: 4) {
                    content()
                }
                .padding(.horizontal, Theme.Dimensions.smallSpacing)
                .padding(.vertical, Theme.Dimensions.smallSpacing)
                .background(Theme.Colors.sidebarExpandedHeaderBackground.opacity(0.60))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 1)
        .background(
            Theme.Colors.sidebarSectionBackground
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(
        title: String,
        icon _: String,
        selection: SidebarSelection,
        countKind: ResourceKind? = nil,
        countOverride: Int? = nil
    ) -> some View {
        let isSelected = appState.sidebarSelection == selection
        let count = countOverride ?? (countKind.flatMap { kindCounts[$0] })

        Button {
            appState.sidebarSelection = selection
        } label: {
            HStack(spacing: Theme.Dimensions.spacing) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Colors.sidebarText : Theme.Colors.sidebarMutedText)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if let count {
                    HStack(spacing: 4) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                isSelected
                                    ? Theme.Colors.sidebarText.opacity(0.9)
                                    : Theme.Colors.sidebarMutedText.opacity(0.85)
                            )
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(isSelected ? Theme.Colors.sidebarText : Theme.Colors.sidebarMutedText)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.Colors.sidebarSelectionBackground : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func crdGroup(title: String, definitions: [CustomResourceDefinitionInfo]) -> some View {
        let isExpanded = expandedCRDGroups.contains(title)

        VStack(spacing: 4) {
            Button {
                if isExpanded {
                    expandedCRDGroups.remove(title)
                } else {
                    expandedCRDGroups.insert(title)
                }
            } label: {
                HStack(spacing: Theme.Dimensions.spacing) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.sidebarMutedText)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.sidebarMutedText)
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(0.015)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                ForEach(definitions.sorted { lhs, rhs in
                    lhs.kind.localizedCaseInsensitiveCompare(rhs.kind) == .orderedAscending
                }) { definition in
                    let target = CustomResourceNavigationTarget(definition: definition)
                    row(
                        title: definition.kind,
                        icon: "puzzlepiece.extension",
                        selection: .customResource(target),
                        countOverride: crdCounts[definition.id]
                    )
                    .padding(.leading, 10)
                }
            }
        }
    }

    private func toggleSection(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }

    private func restoreExpandedState() {
        let defaults = UserDefaults.standard

        if let storedSections = defaults.array(forKey: Self.expandedSectionsDefaultsKey) as? [String], !storedSections.isEmpty {
            expandedSections = Set(storedSections)
        }

        if let storedGroups = defaults.array(forKey: Self.expandedCRDGroupsDefaultsKey) as? [String] {
            expandedCRDGroups = Set(storedGroups)
        }
    }

    private func persistExpandedSections(_ sections: Set<String>) {
        UserDefaults.standard.set(Array(sections).sorted(), forKey: Self.expandedSectionsDefaultsKey)
    }

    private func persistExpandedCRDGroups(_ groups: Set<String>) {
        UserDefaults.standard.set(Array(groups).sorted(), forKey: Self.expandedCRDGroupsDefaultsKey)
    }

    private func startAutoRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await refreshSidebarData()
            }
        }
    }

    @MainActor
    private func refreshSidebarData(showSpinner: Bool = false) async {
        guard !isRefreshing else { return }

        if showSpinner {
            isManualRefreshInProgress = true
        }
        defer {
            if showSpinner {
                isManualRefreshInProgress = false
            }
        }

        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            kindCounts = [:]
            crdDefinitionsByGroup = [:]
            crdCounts = [:]
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let service = KubernetesService(client: client)
        let namespace = appState.selectedNamespace
        let contextName = appState.activeCluster?.contextName

        let kindsToCount: [ResourceKind] = [
            .node, .event,
            .cronJob, .daemonSet, .deployment, .job, .statefulSet, .pod, .replicaSet,
            .horizontalPodAutoscaler, .ingress, .service,
            .persistentVolume, .storageClass, .configMap, .persistentVolumeClaim, .secret,
            .limitRange, .networkPolicy, .podDisruptionBudget, .resourceQuota,
            .endpoint, .namespace, .serviceAccount, .role, .roleBinding, .clusterRole, .clusterRoleBinding,
        ]

        var loadedCounts: [ResourceKind: Int] = [:]
        await withTaskGroup(of: (ResourceKind, Int?).self) { group in
            for kind in kindsToCount {
                group.addTask {
                    let count = await countFor(kind: kind, service: service, namespace: namespace)
                    return (kind, count)
                }
            }

            for await (kind, count) in group {
                if let count {
                    loadedCounts[kind] = count
                }
            }
        }
        kindCounts = loadedCounts

        let definitions: [CustomResourceDefinitionInfo]
        do {
            definitions = try await service.listCustomResourceDefinitions(context: contextName)
        } catch {
            crdDefinitionsByGroup = [:]
            crdCounts = [:]
            return
        }

        crdDefinitionsByGroup = Dictionary(grouping: definitions, by: \.group)

        var loadedCRDCounts: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for definition in definitions {
                group.addTask {
                    do {
                        let items = try await service.listCustomResources(
                            definition: definition,
                            namespace: definition.isNamespaced ? namespace : nil,
                            context: contextName
                        )
                        return (definition.id, items.count)
                    } catch {
                        return (definition.id, nil)
                    }
                }
            }

            for await (definitionID, count) in group {
                if let count {
                    loadedCRDCounts[definitionID] = count
                }
            }
        }
        crdCounts = loadedCRDCounts
    }

    private func countFor(kind: ResourceKind, service: KubernetesService, namespace: String?) async -> Int? {
        do {
            switch kind {
            case .pod:
                return try await service.list(core.v1.Pod.self, in: namespace).items.count
            case .deployment:
                return try await service.list(apps.v1.Deployment.self, in: namespace).items.count
            case .statefulSet:
                return try await service.list(apps.v1.StatefulSet.self, in: namespace).items.count
            case .daemonSet:
                return try await service.list(apps.v1.DaemonSet.self, in: namespace).items.count
            case .job:
                return try await service.list(batch.v1.Job.self, in: namespace).items.count
            case .cronJob:
                return try await service.list(batch.v1.CronJob.self, in: namespace).items.count
            case .replicaSet:
                return try await service.list(apps.v1.ReplicaSet.self, in: namespace).items.count
            case .service:
                return try await service.list(core.v1.Service.self, in: namespace).items.count
            case .ingress:
                return try await service.list(networking.v1.Ingress.self, in: namespace).items.count
            case .endpoint:
                return try await service.list(core.v1.Endpoints.self, in: namespace).items.count
            case .horizontalPodAutoscaler:
                return try await service.list(autoscaling.v2.HorizontalPodAutoscaler.self, in: namespace).items.count
            case .configMap:
                return try await service.list(core.v1.ConfigMap.self, in: namespace).items.count
            case .secret:
                return try await service.list(core.v1.Secret.self, in: namespace).items.count
            case .persistentVolumeClaim:
                return try await service.list(core.v1.PersistentVolumeClaim.self, in: namespace).items.count
            case .serviceAccount:
                return try await service.list(core.v1.ServiceAccount.self, in: namespace).items.count
            case .role:
                return try await service.list(rbac.v1.Role.self, in: namespace).items.count
            case .roleBinding:
                return try await service.list(rbac.v1.RoleBinding.self, in: namespace).items.count
            case .limitRange:
                return try await service.list(core.v1.LimitRange.self, in: namespace).items.count
            case .networkPolicy:
                return try await service.list(networking.v1.NetworkPolicy.self, in: namespace).items.count
            case .podDisruptionBudget:
                return try await service.list(policy.v1.PodDisruptionBudget.self, in: namespace).items.count
            case .resourceQuota:
                return try await service.list(core.v1.ResourceQuota.self, in: namespace).items.count
            case .event:
                return try await service.list(core.v1.Event.self, in: namespace).items.count
            case .node:
                return try await service.listClusterScoped(core.v1.Node.self).items.count
            case .namespace:
                return try await service.listClusterScoped(core.v1.Namespace.self).items.count
            case .persistentVolume:
                return try await service.listClusterScoped(core.v1.PersistentVolume.self).items.count
            case .storageClass:
                return try await service.listClusterScoped(storage.v1.StorageClass.self).items.count
            case .clusterRole:
                return try await service.listClusterScoped(rbac.v1.ClusterRole.self).items.count
            case .clusterRoleBinding:
                return try await service.listClusterScoped(rbac.v1.ClusterRoleBinding.self).items.count
            }
        } catch {
            return nil
        }
    }

}
