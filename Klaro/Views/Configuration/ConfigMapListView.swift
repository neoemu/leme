import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct ConfigMapListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()
    @State private var resourceToDelete: ResourceItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading config maps...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Config Maps",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No Config Maps",
                    message: "No config maps found in the selected namespace."
                )
            } else {
                configMapTable
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: appState.selectedNamespace) { _, _ in
            Task {
                await loadData()
            }
        }
        .confirmationDialog(
            "Delete \(resourceToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let resource = resourceToDelete {
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        await viewModel.deleteResource(kind: .configMap, name: resource.name, namespace: resource.namespace, client: client)
                    }
                }
                resourceToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                resourceToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: $viewModel.showDeleteError) {
            Button("OK") {}
        } message: {
            Text(viewModel.deleteError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: ResourceKind.configMap.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Config Maps")
                .font(Theme.Fonts.title)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
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

            Text("\(viewModel.filteredResources.count) items")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Table

    private var configMapTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Name") { item in
                Text(item.name)
                    .font(Theme.Fonts.monoSmall)
                    .contextMenu {
                        Button(role: .destructive) {
                            resourceToDelete = item
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .width(min: 120, ideal: 200)

            TableColumn("Namespace") { item in
                Text(item.namespace ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Data Keys") { item in
                Text(item.extraColumns["dataKeys"] ?? "0")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Age") { item in
                if let age = item.age {
                    AgeLabel(date: age)
                } else {
                    Text("-")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .width(min: 40, ideal: 60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onChange(of: viewModel.selectedResourceID) { _, newValue in
            appState.selectResource(newValue)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
            return
        }

        await viewModel.loadNamespacedResources(
            core.v1.ConfigMap.self,
            kind: .configMap,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: configMapToResourceItem
        )
    }

    private nonisolated func configMapToResourceItem(_ configMap: core.v1.ConfigMap) -> ResourceItem {
        let dataCount = configMap.data?.count ?? 0

        var extra: [String: String] = [:]
        extra["dataKeys"] = "\(dataCount)"

        return ResourceItem(
            id: "\(configMap.metadata?.namespace ?? "")/\(configMap.name ?? "")",
            name: configMap.name ?? "",
            namespace: configMap.metadata?.namespace,
            status: "Active",
            age: configMap.metadata?.creationTimestamp,
            labels: configMap.metadata?.labels ?? [:],
            annotations: configMap.metadata?.annotations ?? [:],
            kind: .configMap,
            extraColumns: extra
        )
    }
}
