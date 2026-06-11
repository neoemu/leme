import SwiftUI

/// Cmd+K overlay: searches resources by name across all namespaces and the
/// main resource kinds of the active cluster, and navigates on selection.
struct GlobalSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var viewModel = GlobalSearchViewModel()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .frame(width: 560)
            .frame(maxHeight: 420)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isSearchFieldFocused = true
            Task {
                guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
                await viewModel.loadIndex(client: client, contextName: appState.activeCluster?.contextName)
            }
        }
        .onDisappear {
            viewModel.clear()
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveDown()
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.secondaryText)
                .font(.system(size: 16, weight: .medium))

            TextField("Search resources in cluster...", text: Bindable(viewModel).searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFieldFocused)
                .onChange(of: viewModel.searchText) {
                    viewModel.selectedIndex = 0
                }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.indexedCount > 0 {
                Text("\(viewModel.indexedCount) resources")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = viewModel.filteredResults
                    if results.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            resultRow(result, isSelected: index == viewModel.selectedIndex)
                                .id(result.id)
                                .onTapGesture {
                                    viewModel.selectedIndex = index
                                    openSelected()
                                }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, _ in
                let results = viewModel.filteredResults
                if viewModel.selectedIndex >= 0 && viewModel.selectedIndex < results.count {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(results[viewModel.selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(_ result: GlobalSearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.iconName)
                .frame(width: 20)
                .foregroundStyle(isSelected ? .white : Theme.Colors.secondaryText)
                .font(.system(size: 13))

            Text(result.name)
                .font(Theme.Fonts.sidebarItem)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let namespace = result.namespace {
                Text(namespace)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : Theme.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Text(result.kindLabel)
                .font(Theme.Fonts.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.7) : Theme.Colors.tertiaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.15) : Color.gray.opacity(0.15))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(viewModel.searchText.isEmpty
                ? "Type to search across all namespaces"
                : (viewModel.isLoading ? "Indexing cluster resources..." : "No matching resources"))
                .font(Theme.Fonts.sidebarItem)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func openSelected() {
        let results = viewModel.filteredResults
        guard viewModel.selectedIndex >= 0, viewModel.selectedIndex < results.count else { return }
        let result = results[viewModel.selectedIndex]

        if result.isHelmRelease {
            // Helm releases live in Installed Apps; select the row there
            // (release details open from that view, not the inspector).
            appState.selectedNamespace = result.namespace
            appState.sidebarSelection = .helmReleases
            appState.selectResource(result.resourceID)
        } else {
            appState.selectedNamespace = result.namespace
            appState.sidebarSelection = .resource(result.kind)
            appState.showResourceDetail(result.resourceID)
        }
        dismiss()
    }

    private func dismiss() {
        appState.isGlobalSearchOpen = false
    }
}
