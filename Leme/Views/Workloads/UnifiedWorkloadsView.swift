import Foundation
import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct UnifiedWorkloadsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()
    @State private var isLoadingWorkloads = false
    @State private var workloadWatcher: ResourceWatcher?
    @State private var watchTasks: [Task<Void, Never>] = []
    @State private var liveReloadTask: Task<Void, Never>?
    @State private var periodicRefreshTask: Task<Void, Never>?
    @State private var isLiveReloading = false

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "State", key: "status", width: 80, sortField: .status),
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Type", key: "kind", width: 100),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 120, sortField: .namespace),
        ResourceTableColumn(title: "Image", key: "image", width: 200),
        ResourceTableColumn(title: "Restarts", key: "restarts", width: 70),
        ResourceTableColumn(title: "Age", key: "age", width: 60, sortField: .age),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()
                .padding(.top, Theme.Dimensions.spacing)

            ResourceTableView(
                columns: columns,
                viewModel: viewModel,
                onViewYAML: { resource in
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        do {
                            let yaml = try await viewModel.fetchResourceYAML(
                                kind: resource.kind,
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
                groupByNamespace: true
            )
        }
        .task {
            await loadAllWorkloads()
            await startLiveUpdates()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadAllWorkloads()
                await startLiveUpdates()
            }
        }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task {
                await loadAllWorkloads()
                await startLiveUpdates()
            }
        }
        .onDisappear {
            stopLiveUpdates()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("All Workloads")
                .font(Theme.Fonts.title)

            Spacer()

            if isLoadingWorkloads {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(viewModel.resources.count) workloads")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Data Loading

    private func loadAllWorkloads(showLoading: Bool = true) async {
        let isLiveReloadRequest = !showLoading
        if isLiveReloadRequest {
            guard !isLiveReloading else { return }
            isLiveReloading = true
        }
        defer {
            if isLiveReloadRequest {
                isLiveReloading = false
            }
        }

        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        if showLoading {
            isLoadingWorkloads = true
            viewModel.isLoading = true
        }
        viewModel.errorMessage = nil

        let service = KubernetesService(client: client)
        let namespace = appState.filteredNamespace

        // Load all workload types concurrently
        async let podsResult: core.v1.PodList? = {
            try? await service.list(core.v1.Pod.self, in: namespace)
        }()

        async let deploymentsResult: apps.v1.DeploymentList? = {
            try? await service.list(apps.v1.Deployment.self, in: namespace)
        }()

        async let statefulSetsResult: apps.v1.StatefulSetList? = {
            try? await service.list(apps.v1.StatefulSet.self, in: namespace)
        }()

        async let daemonSetsResult: apps.v1.DaemonSetList? = {
            try? await service.list(apps.v1.DaemonSet.self, in: namespace)
        }()

        async let jobsResult: batch.v1.JobList? = {
            try? await service.list(batch.v1.Job.self, in: namespace)
        }()

        async let cronJobsResult: batch.v1.CronJobList? = {
            try? await service.list(batch.v1.CronJob.self, in: namespace)
        }()

        async let replicaSetsResult: apps.v1.ReplicaSetList? = {
            try? await service.list(apps.v1.ReplicaSet.self, in: namespace)
        }()

        let pods = await podsResult
        let deployments = await deploymentsResult
        let statefulSets = await statefulSetsResult
        let daemonSets = await daemonSetsResult
        let jobs = await jobsResult
        let cronJobs = await cronJobsResult
        let replicaSets = await replicaSetsResult

        var allItems: [ResourceItem] = []

        // Map pods
        for pod in pods?.items ?? [] {
            let restarts = PodStatusFormatter.restartCount(for: pod)
            let status = PodStatusFormatter.displayStatus(for: pod)
            let image = pod.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "pod/\(pod.metadata?.namespace ?? "")/\(pod.name ?? "")",
                name: pod.name ?? "",
                namespace: pod.metadata?.namespace,
                status: status,
                age: pod.metadata?.creationTimestamp,
                labels: pod.metadata?.labels ?? [:],
                annotations: pod.metadata?.annotations ?? [:],
                kind: .pod,
                extraColumns: [
                    "kind": "Pod",
                    "image": image,
                    "restarts": "\(restarts)",
                ]
            ))
        }

        // Map deployments
        for deploy in deployments?.items ?? [] {
            let ready = deploy.status?.readyReplicas ?? 0
            let replicas = deploy.spec?.replicas ?? 0
            let status = ready == replicas && replicas > 0 ? "Running" : (replicas == 0 ? "Scaled Down" : "Updating")
            let image = deploy.spec?.template.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "deploy/\(deploy.metadata?.namespace ?? "")/\(deploy.name ?? "")",
                name: deploy.name ?? "",
                namespace: deploy.metadata?.namespace,
                status: status,
                age: deploy.metadata?.creationTimestamp,
                labels: deploy.metadata?.labels ?? [:],
                annotations: deploy.metadata?.annotations ?? [:],
                kind: .deployment,
                extraColumns: [
                    "kind": "Deployment",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        // Map stateful sets
        for sts in statefulSets?.items ?? [] {
            let ready = sts.status?.readyReplicas ?? 0
            let replicas = sts.spec?.replicas ?? 0
            let status = ready == replicas && replicas > 0 ? "Running" : "Updating"
            let image = sts.spec?.template.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "sts/\(sts.metadata?.namespace ?? "")/\(sts.name ?? "")",
                name: sts.name ?? "",
                namespace: sts.metadata?.namespace,
                status: status,
                age: sts.metadata?.creationTimestamp,
                labels: sts.metadata?.labels ?? [:],
                annotations: sts.metadata?.annotations ?? [:],
                kind: .statefulSet,
                extraColumns: [
                    "kind": "StatefulSet",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        // Map daemon sets
        for ds in daemonSets?.items ?? [] {
            let desired = ds.status?.desiredNumberScheduled ?? 0
            let ready = ds.status?.numberReady ?? 0
            let status = ready == desired ? "Running" : "Updating"
            let image = ds.spec?.template.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "ds/\(ds.metadata?.namespace ?? "")/\(ds.name ?? "")",
                name: ds.name ?? "",
                namespace: ds.metadata?.namespace,
                status: status,
                age: ds.metadata?.creationTimestamp,
                labels: ds.metadata?.labels ?? [:],
                annotations: ds.metadata?.annotations ?? [:],
                kind: .daemonSet,
                extraColumns: [
                    "kind": "DaemonSet",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        // Map jobs
        for job in jobs?.items ?? [] {
            let succeeded = job.status?.succeeded ?? 0
            let status = succeeded > 0 ? "Completed" : "Running"
            let image = job.spec?.template.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "job/\(job.metadata?.namespace ?? "")/\(job.name ?? "")",
                name: job.name ?? "",
                namespace: job.metadata?.namespace,
                status: status,
                age: job.metadata?.creationTimestamp,
                labels: job.metadata?.labels ?? [:],
                annotations: job.metadata?.annotations ?? [:],
                kind: .job,
                extraColumns: [
                    "kind": "Job",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        // Map cron jobs
        for cj in cronJobs?.items ?? [] {
            let suspended = cj.spec?.suspend ?? false
            let status = suspended ? "Suspended" : "Active"
            let image = cj.spec?.jobTemplate.spec?.template.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "cj/\(cj.metadata?.namespace ?? "")/\(cj.name ?? "")",
                name: cj.name ?? "",
                namespace: cj.metadata?.namespace,
                status: status,
                age: cj.metadata?.creationTimestamp,
                labels: cj.metadata?.labels ?? [:],
                annotations: cj.metadata?.annotations ?? [:],
                kind: .cronJob,
                extraColumns: [
                    "kind": "CronJob",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        // Map replica sets (only those not owned by a deployment)
        for rs in replicaSets?.items ?? [] {
            let ownerRefs = rs.metadata?.ownerReferences ?? []
            let ownedByDeployment = ownerRefs.contains { $0.kind == "Deployment" }
            guard !ownedByDeployment else { continue }

            let ready = rs.status?.readyReplicas ?? 0
            let replicas = rs.spec?.replicas ?? 0
            let status = ready == replicas && replicas > 0 ? "Running" : "Updating"
            let image = rs.spec?.template?.spec?.containers.first?.image ?? ""

            allItems.append(ResourceItem(
                id: "rs/\(rs.metadata?.namespace ?? "")/\(rs.name ?? "")",
                name: rs.name ?? "",
                namespace: rs.metadata?.namespace,
                status: status,
                age: rs.metadata?.creationTimestamp,
                labels: rs.metadata?.labels ?? [:],
                annotations: rs.metadata?.annotations ?? [:],
                kind: .replicaSet,
                extraColumns: [
                    "kind": "ReplicaSet",
                    "image": image,
                    "restarts": "-",
                ]
            ))
        }

        viewModel.resources = allItems
        if showLoading {
            viewModel.isLoading = false
            isLoadingWorkloads = false
        }
    }

    private func startLiveUpdates() async {
        stopLiveUpdates()

        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        let namespace = appState.filteredNamespace
        let watcher = ResourceWatcher(client: client)
        workloadWatcher = watcher
        await MainActor.run {
            viewModel.liveWatchStatus = .syncing
        }

        let watchStreams: [AsyncStream<MappedWatchEvent>] = await [
            watcher.watchMapped(core.v1.Pod.self, kind: .pod, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .pod)),
            watcher.watchMapped(apps.v1.Deployment.self, kind: .deployment, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .deployment)),
            watcher.watchMapped(apps.v1.StatefulSet.self, kind: .statefulSet, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .statefulSet)),
            watcher.watchMapped(apps.v1.DaemonSet.self, kind: .daemonSet, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .daemonSet)),
            watcher.watchMapped(batch.v1.Job.self, kind: .job, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .job)),
            watcher.watchMapped(batch.v1.CronJob.self, kind: .cronJob, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .cronJob)),
            watcher.watchMapped(apps.v1.ReplicaSet.self, kind: .replicaSet, in: namespace, mapper: ResourceWatcher.signalMapper(kind: .replicaSet)),
        ]

        for stream in watchStreams {
            let task = Task {
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        if case .error(let reason) = event.change {
                            viewModel.liveWatchStatus = .recovering(lastEventAt: nil, reason: reason)
                            return
                        }
                        viewModel.liveWatchStatus = .live(lastEventAt: Date())
                        scheduleLiveReload()
                    }
                }
            }
            watchTasks.append(task)
        }

        periodicRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.resourceRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await loadAllWorkloads(showLoading: false)
            }
        }
    }

    private func scheduleLiveReload() {
        liveReloadTask?.cancel()
        liveReloadTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadAllWorkloads(showLoading: false)
        }
    }

    private func stopLiveUpdates() {
        watchTasks.forEach { $0.cancel() }
        watchTasks.removeAll()

        liveReloadTask?.cancel()
        liveReloadTask = nil
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil

        if let workloadWatcher {
            Task {
                await workloadWatcher.stopAll()
            }
        }
        workloadWatcher = nil
        viewModel.liveWatchStatus = .off
    }
}
