import SwiftUI

/// "Installed Apps": helm releases of the active cluster, following the
/// shared resource-table contract (see docs/ui-consistency.md).
struct HelmReleaseListView: View {
    @Environment(AppState.self) private var appState

    @State private var viewModel = ResourceListViewModel()
    @State private var releasesByID: [String: HelmRelease] = [:]
    @State private var detailTarget: HelmReleaseDetailTarget?

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Namespace", key: "namespace", width: 150, sortField: .namespace),
        ResourceTableColumn(title: "Status", key: "status", width: 120, sortField: .status),
        ResourceTableColumn(title: "Chart", key: "chart", width: 190),
        ResourceTableColumn(title: "App Version", key: "appVersion", width: 90),
        ResourceTableColumn(title: "Revision", key: "revision", width: 70),
        ResourceTableColumn(title: "Updated", key: "age", width: 80, sortField: .age),
    ]

    private var helmService: HelmService {
        HelmService(contextName: appState.activeCluster?.contextName)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ResourceTableView(
                columns: columns,
                viewModel: viewModel,
                extraActions: { resource in rowActions(for: resource) },
                onShowDetails: { resource in
                    openDetail(for: resource, tab: .history)
                }
            )
        }
        .task { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
        .sheet(item: $detailTarget) { target in
            HelmReleaseDetailSheet(
                release: target.release,
                initialTab: target.tab,
                service: helmService
            ) {
                Task { await loadData() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Installed Apps")
                .font(Theme.Fonts.title)

            Text("Helm")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .fill(Color.secondary.opacity(0.12))
                )

            Spacer()

            if let namespace = appState.selectedNamespace {
                Text(namespace)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }

            Button {
                Task { await loadData() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help("Refresh releases")
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.padding)
    }

    private func rowActions(for resource: ResourceItem) -> [ResourceRowAction] {
        guard let release = releasesByID[resource.id] else { return [] }

        return [
            ResourceRowAction(title: "History & Rollback…", icon: "clock.arrow.circlepath") {
                openDetail(for: resource, tab: .history)
            },
            ResourceRowAction(title: "Values", icon: "doc.text") {
                openDetail(for: resource, tab: .values)
            },
            ResourceRowAction(title: "Manifest", icon: "doc.plaintext") {
                openDetail(for: resource, tab: .manifest)
            },
            ResourceRowAction(
                title: "Uninstall Release…",
                icon: "trash",
                isDestructive: true,
                needsConfirmation: true,
                confirmationMessage: "Uninstall helm release \(release.name) from namespace \(release.namespace)? This deletes all resources managed by the chart and cannot be undone."
            ) {
                Task { await uninstall(release) }
            },
        ]
    }

    private func openDetail(for resource: ResourceItem, tab: HelmReleaseDetailSheet.Tab) {
        guard let release = releasesByID[resource.id] else { return }
        detailTarget = HelmReleaseDetailTarget(release: release, tab: tab)
    }

    @MainActor
    private func loadData() async {
        guard appState.activeCluster != nil else { return }
        viewModel.isLoading = true
        viewModel.errorMessage = nil
        do {
            let releases = try await helmService.listReleases(namespace: appState.selectedNamespace)
            releasesByID = Dictionary(releases.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            viewModel.resources = releases.map(resourceItem(from:))
        } catch {
            viewModel.resources = []
            releasesByID = [:]
            viewModel.errorMessage = error.localizedDescription
        }
        viewModel.isLoading = false
    }

    @MainActor
    private func uninstall(_ release: HelmRelease) async {
        viewModel.operationState = .running("Uninstalling \(release.name)…")
        do {
            try await helmService.uninstall(releaseName: release.name, namespace: release.namespace)
            viewModel.operationState = .success("Uninstalled \(release.name)")
            await loadData()
        } catch {
            viewModel.operationState = .error("Uninstall failed: \(error.localizedDescription)")
        }
    }

    private func resourceItem(from release: HelmRelease) -> ResourceItem {
        // `kind` is required by the shared table but unused here: helm rows
        // override details and define their own actions.
        ResourceItem(
            id: release.id,
            name: release.name,
            namespace: release.namespace,
            status: release.displayStatus,
            age: release.updated,
            labels: [:],
            annotations: [:],
            kind: .endpoint,
            extraColumns: [
                "chart": release.chart,
                "appVersion": release.appVersion,
                "revision": String(release.revision),
            ]
        )
    }
}

private struct HelmReleaseDetailTarget: Identifiable {
    let release: HelmRelease
    let tab: HelmReleaseDetailSheet.Tab

    var id: String { release.id }
}
