import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct EventListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ResourceListViewModel()
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.top, Theme.Dimensions.padding)

            Divider()

            if viewModel.isLoading && viewModel.resources.isEmpty {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error Loading Events",
                    message: errorMessage
                )
            } else if viewModel.filteredResources.isEmpty {
                EmptyStateView(
                    icon: "bell.slash",
                    title: "No Events",
                    message: "No events found in the selected namespace."
                )
            } else {
                eventTable
            }
        }
        .task {
            await loadData()
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
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
            Image(systemName: ResourceKind.event.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Events")
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

            Text("\(viewModel.filteredResources.count) events")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Colors.tertiaryText)
                .help("Auto-refreshes every 10 seconds")
        }
    }

    // MARK: - Table

    private var eventTable: some View {
        Table(viewModel.filteredResources, selection: $viewModel.selectedResourceID) {
            TableColumn("Type") { event in
                StatusBadge(status: event.status)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Reason") { event in
                Text(event.extraColumns["reason"] ?? "")
                    .font(Theme.Fonts.tableCell)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Object") { event in
                Text(event.extraColumns["object"] ?? "")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Message") { event in
                Text(event.extraColumns["message"] ?? "")
                    .font(Theme.Fonts.tableCell)
                    .lineLimit(2)
            }
            .width(min: 150, ideal: 300)

            TableColumn("Count") { event in
                Text(event.extraColumns["count"] ?? "0")
                    .font(Theme.Fonts.monoSmall)
            }
            .width(min: 40, ideal: 50)

            TableColumn("Last Seen") { event in
                if let age = event.age {
                    AgeLabel(date: age)
                } else {
                    Text("-")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .width(min: 50, ideal: 70)
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
            core.v1.Event.self,
            kind: .event,
            client: client,
            namespace: appState.selectedNamespace,
            mapper: eventToResourceItem
        )
    }

    private nonisolated func eventToResourceItem(_ event: core.v1.Event) -> ResourceItem {
        var extra: [String: String] = [:]
        extra["reason"] = event.reason ?? ""
        extra["message"] = event.message ?? ""
        extra["count"] = "\(event.count ?? 0)"
        extra["object"] = "\(event.involvedObject.kind ?? "")/\(event.involvedObject.name ?? "")"

        // Use lastTimestamp if available, fall back to creationTimestamp
        let lastSeen = event.lastTimestamp ?? event.metadata?.creationTimestamp

        return ResourceItem(
            id: "\(event.metadata?.namespace ?? "")/\(event.name ?? "")",
            name: event.name ?? "",
            namespace: event.metadata?.namespace,
            status: event.type ?? "Normal",
            age: lastSeen,
            labels: event.metadata?.labels ?? [:],
            annotations: event.metadata?.annotations ?? [:],
            kind: .event,
            extraColumns: extra
        )
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await loadData()
            }
        }
    }
}
