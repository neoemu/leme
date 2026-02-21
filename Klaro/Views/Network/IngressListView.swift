import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct IngressListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon, title, search
            HStack {
                Image(systemName: ResourceKind.ingress.icon)
                    .foregroundStyle(Theme.Colors.accent)
                Text(ResourceKind.ingress.pluralName)
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
                    icon: "arrow.right.to.line",
                    title: "No Ingresses",
                    message: "No ingresses found in the current namespace."
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
                    TableColumn("Hosts") { item in
                        Text(item.extraColumns["hosts"] ?? "")
                            .font(Theme.Fonts.tableCell)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    TableColumn("Paths") { item in
                        Text(item.extraColumns["paths"] ?? "")
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
            networking.v1.Ingress.self,
            kind: .ingress,
            client: client,
            namespace: appState.selectedNamespace
        ) { resource in
            let rules = resource.spec?.rules ?? []
            let hosts = rules.compactMap { $0.host }.joined(separator: ", ")
            let paths = rules.flatMap { rule in
                (rule.http?.paths ?? []).map { $0.path ?? "/" }
            }.joined(separator: ", ")

            return ResourceItem(
                id: "\(resource.metadata?.namespace ?? "")/\(resource.name ?? "")",
                name: resource.name ?? "",
                namespace: resource.metadata?.namespace,
                status: "Active",
                age: resource.metadata?.creationTimestamp,
                labels: resource.metadata?.labels ?? [:],
                annotations: resource.metadata?.annotations ?? [:],
                kind: .ingress,
                extraColumns: [
                    "hosts": hosts,
                    "paths": paths,
                ]
            )
        }
    }
}
