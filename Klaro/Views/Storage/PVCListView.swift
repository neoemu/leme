import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct PVCListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.persistentVolumeClaim.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.persistentVolumeClaim.pluralName)
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
                    icon: "externaldrive",
                    title: "No Persistent Volume Claims",
                    message: "No PVCs found in the current namespace."
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
                    TableColumn("Namespace") { item in
                        Text(item.namespace ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Status") { item in
                        StatusBadge(status: item.status)
                    }
                    TableColumn("Volume") { item in
                        Text(item.extraColumns["volume"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Capacity") { item in
                        Text(item.extraColumns["capacity"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Storage Class") { item in
                        Text(item.extraColumns["storageClass"] ?? "")
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
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadNamespacedResources(
            core.v1.PersistentVolumeClaim.self,
            kind: .persistentVolumeClaim,
            client: client,
            namespace: appState.selectedNamespace
        ) { resource in
            let phase = resource.status?.phase ?? "Unknown"
            let volume = resource.spec?.volumeName ?? ""
            let capacity: String
            if let qty = resource.status?.capacity?["storage"] {
                capacity = qty.description
            } else {
                capacity = ""
            }
            let storageClass = resource.spec?.storageClassName ?? ""

            return ResourceItem(
                id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
                name: resource.name ?? "",
                namespace: resource.metadata?.namespace,
                status: phase,
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .persistentVolumeClaim,
                extraColumns: [
                    "volume": volume,
                    "capacity": capacity,
                    "storageClass": storageClass,
                ]
            )
        }
    }
}
