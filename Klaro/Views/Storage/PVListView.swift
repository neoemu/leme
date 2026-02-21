import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct PVListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.persistentVolume.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.persistentVolume.pluralName)
                    .font(Theme.Fonts.title)
                Spacer()
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "internaldrive",
                    title: "No Persistent Volumes",
                    message: "No persistent volumes found in the cluster."
                )
            } else {
                Table(viewModel.filteredResources, selection: Binding(
                    get: { appState.selectedResourceID },
                    set: { appState.selectResource($0) }
                )) {
                    TableColumn("Name") { item in
                        Text(item.name)
                            .font(Theme.Fonts.tableCell)
                    }
                    TableColumn("Capacity") { item in
                        Text(item.extraColumns["capacity"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Access Modes") { item in
                        Text(item.extraColumns["accessModes"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Reclaim Policy") { item in
                        Text(item.extraColumns["reclaimPolicy"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Status") { item in
                        StatusBadge(status: item.status)
                    }
                    TableColumn("Claim") { item in
                        Text(item.extraColumns["claim"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Age") { item in
                        if let date = item.age {
                            AgeLabel(date: date)
                        } else {
                            Text("-")
                                .font(Theme.Fonts.tableCell)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
                .font(Theme.Fonts.tableCell)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadClusterScopedResources(
            core.v1.PersistentVolume.self,
            kind: .persistentVolume,
            client: client
        ) { resource in
            let capacity: String
            if let qty = resource.spec?.capacity?["storage"] {
                capacity = qty.description
            } else {
                capacity = ""
            }
            let accessModes = (resource.spec?.accessModes ?? []).joined(separator: ", ")
            let reclaimPolicy = resource.spec?.persistentVolumeReclaimPolicy ?? ""
            let phase = resource.status?.phase ?? "Unknown"
            let claimRef = resource.spec?.claimRef
            let claim: String
            if let ns = claimRef?.namespace, let name = claimRef?.name {
                claim = "\(ns)/\(name)"
            } else {
                claim = ""
            }

            return ResourceItem(
                id: resource.name ?? "",
                name: resource.name ?? "",
                namespace: nil,
                status: phase,
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .persistentVolume,
                extraColumns: [
                    "capacity": capacity,
                    "accessModes": accessModes,
                    "reclaimPolicy": reclaimPolicy,
                    "claim": claim,
                ]
            )
        }
    }
}
