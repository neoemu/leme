import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct StorageClassListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.storageClass.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.storageClass.pluralName)
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
                    icon: "cylinder",
                    title: "No Storage Classes",
                    message: "No storage classes found in the cluster."
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
                    TableColumn("Provisioner") { item in
                        Text(item.extraColumns["provisioner"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Reclaim Policy") { item in
                        Text(item.extraColumns["reclaimPolicy"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Default") { item in
                        Text(item.extraColumns["default"] ?? "No")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
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
            storage.v1.StorageClass.self,
            kind: .storageClass,
            client: client
        ) { resource in
            let provisioner = resource.provisioner
            let reclaimPolicy = resource.reclaimPolicy ?? ""
            let annotations = resource.metadata?.annotations ?? [:]
            let isDefault = annotations["storageclass.kubernetes.io/is-default-class"] == "true"

            return ResourceItem(
                id: resource.name ?? "",
                name: resource.name ?? "",
                namespace: nil,
                status: "Active",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: annotations,
                kind: .storageClass,
                extraColumns: [
                    "provisioner": provisioner,
                    "reclaimPolicy": reclaimPolicy,
                    "default": isDefault ? "Yes" : "No",
                ]
            )
        }
    }
}
