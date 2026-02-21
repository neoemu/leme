import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct SecretListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading secrets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Secrets",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "lock",
                    title: "No Secrets",
                    message: "No secrets found in the selected namespace."
                )
            } else {
                secretTable
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: ResourceKind.secret.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Secrets")
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

    private var secretTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Name") { item in
                HStack(spacing: Theme.Dimensions.smallSpacing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(item.name)
                        .font(Theme.Fonts.monoSmall)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("Namespace") { item in
                Text(item.namespace ?? "-")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Type") { item in
                Text(item.extraColumns["type"] ?? "Opaque")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .width(min: 100, ideal: 160)

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
            core.v1.Secret.self,
            kind: .secret,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: secretToResourceItem
        )
    }

    private nonisolated func secretToResourceItem(_ secret: core.v1.Secret) -> ResourceItem {
        let dataCount = secret.data?.count ?? 0
        let secretType = secret.type ?? "Opaque"

        var extra: [String: String] = [:]
        extra["type"] = secretType
        extra["dataKeys"] = "\(dataCount)"
        // Values are intentionally masked - we never expose secret data

        return ResourceItem(
            id: "\(secret.metadata?.namespace ?? "")/\(secret.name ?? "")",
            name: secret.name ?? "",
            namespace: secret.metadata?.namespace,
            status: "Active",
            age: secret.metadata?.creationTimestamp,
            labels: secret.metadata?.labels ?? [:],
            annotations: secret.metadata?.annotations ?? [:],
            kind: .secret,
            extraColumns: extra
        )
    }
}
