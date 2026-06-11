import SwiftUI
import SwiftkubeClient
import SwiftkubeModel

struct NamespaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = ResourceListViewModel()
    @State private var isCreateSheetPresented = false

    private let columns: [ResourceTableColumn] = [
        ResourceTableColumn(title: "Name", key: "name", sortField: .name),
        ResourceTableColumn(title: "Status", key: "status", width: 120, sortField: .status),
        ResourceTableColumn(title: "Age", key: "age", width: 70, sortField: .age),
    ]

    var body: some View {
        VStack(spacing: 0) {
            actionStrip

            ResourceTableView(
                columns: columns,
                viewModel: viewModel,
                onViewYAML: { resource in
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        do {
                            let yaml = try await viewModel.fetchResourceYAML(
                                kind: .namespace,
                                name: resource.name,
                                namespace: nil,
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
                onDelete: { resource in
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        await viewModel.deleteResource(kind: .namespace, name: resource.name, namespace: nil, client: client)
                        if appState.selectedNamespace == resource.name {
                            appState.selectedNamespace = nil
                        }
                        await refreshNamespaceFilter()
                    }
                },
                onDownloadYAML: { resource in
                    Task {
                        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                        await viewModel.downloadResourceYAML(kind: .namespace, name: resource.name, namespace: nil, client: client)
                    }
                },
                extraActions: { resource in
                    [
                        ResourceRowAction(title: "Use as Namespace Filter", icon: "line.3.horizontal.decrease.circle") {
                            appState.selectedNamespace = resource.name
                        },
                    ]
                },
                deleteConfirmationMessageBuilder: { resource in
                    "Namespace: \(resource.name)\n\nDeleting a namespace removes EVERY resource inside it. This action cannot be undone."
                }
            )
        }
        .task { await loadData() }
        .onChange(of: appState.activeClusterID) { _, _ in
            Task { await loadData() }
        }
        .sheet(isPresented: $isCreateSheetPresented) {
            CreateNamespaceSheet { name in
                await createNamespace(named: name)
            }
        }
    }

    private var actionStrip: some View {
        HStack {
            Spacer()
            Button {
                isCreateSheetPresented = true
            } label: {
                Label("New Namespace", systemImage: "plus")
                    .font(Theme.Fonts.sidebarItem)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.top, Theme.Dimensions.smallSpacing)
    }

    private func loadData() async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.loadClusterScopedResources(
            core.v1.Namespace.self,
            kind: .namespace,
            client: client
        ) { namespace in
            let name = namespace.name ?? ""
            return ResourceItem(
                id: name,
                name: name,
                namespace: nil,
                status: namespace.status?.phase ?? "Active",
                age: namespace.metadata?.creationTimestamp,
                labels: namespace.metadata?.labels ?? [:],
                annotations: namespace.metadata?.annotations ?? [:],
                kind: .namespace
            )
        }
    }

    @MainActor
    private func createNamespace(named name: String) async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        viewModel.operationState = .running("Creating namespace \(name)…")
        do {
            let service = KubernetesService(client: client, contextName: appState.activeCluster?.contextName)
            try await service.createNamespace(name: name)
            viewModel.operationState = .success("Created namespace \(name)")
            await refreshNamespaceFilter()
        } catch {
            viewModel.operationState = .error("Create failed: \(error.localizedDescription)")
        }
    }

    /// Keeps the sidebar namespace dropdown in sync after create/delete.
    private func refreshNamespaceFilter() async {
        guard let clusterID = appState.activeClusterID else { return }
        await clusterViewModel.refreshNamespaces(for: clusterID, appState: appState)
    }
}

private struct CreateNamespaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String) async -> Void

    @State private var name = ""
    @State private var isCreating = false
    @FocusState private var isFieldFocused: Bool

    /// DNS-1123 label: lowercase alphanumerics and '-', must start/end
    /// alphanumeric, at most 63 characters.
    private var isValidName: Bool {
        guard !name.isEmpty, name.count <= 63 else { return false }
        guard let first = name.first, let last = name.last,
              first.isLetter || first.isNumber,
              last.isLetter || last.isNumber else { return false }
        return name.allSatisfy { character in
            (character.isLowercase && character.isLetter) || character.isNumber || character == "-"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
            Text("New Namespace")
                .font(Theme.Fonts.title)

            VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
                TextField("namespace-name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.monoSmall)
                    .focused($isFieldFocused)
                    .onSubmit {
                        if isValidName {
                            create()
                        }
                    }

                Text("Lowercase letters, numbers and '-', starting and ending alphanumeric (max 63 chars).")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(
                        name.isEmpty || isValidName
                            ? Theme.Colors.secondaryText
                            : Theme.Colors.failed
                    )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isCreating ? "Creating…" : "Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValidName || isCreating)
            }
        }
        .padding(Theme.Dimensions.sectionSpacing)
        .frame(width: 380)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func create() {
        isCreating = true
        let namespaceName = name
        Task {
            await onCreate(namespaceName)
            isCreating = false
            dismiss()
        }
    }
}
