import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = CommandPaletteViewModel()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed background overlay
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Palette card
            VStack(spacing: 0) {
                searchField
                Divider()
                actionsList
            }
            .frame(width: 500)
            .frame(maxHeight: 400)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            viewModel.buildActions(appState: appState)
            isSearchFieldFocused = true
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
            viewModel.executeSelected(appState: appState)
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

            TextField("Type a command...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFieldFocused)
                .onChange(of: viewModel.searchText) {
                    viewModel.selectedIndex = 0
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions List

    private var actionsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let filtered = viewModel.filteredActions
                    let grouped = Dictionary(grouping: filtered) { $0.category }
                    let sortedCategories = categoryOrder.filter { grouped.keys.contains($0) }

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(sortedCategories, id: \.self) { category in
                            if let categoryActions = grouped[category] {
                                categoryHeader(category)
                                ForEach(categoryActions) { action in
                                    let index = filtered.firstIndex(where: { $0.id == action.id }) ?? 0
                                    actionRow(action: action, isSelected: index == viewModel.selectedIndex)
                                        .id(action.id)
                                        .onTapGesture {
                                            viewModel.selectedIndex = index
                                            viewModel.executeSelected(appState: appState)
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, _ in
                let filtered = viewModel.filteredActions
                if viewModel.selectedIndex >= 0 && viewModel.selectedIndex < filtered.count {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(filtered[viewModel.selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Category Header

    private func categoryHeader(_ category: String) -> some View {
        Text(category.uppercased())
            .font(Theme.Fonts.sidebarHeader)
            .foregroundStyle(Theme.Colors.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Action Row

    private func actionRow(action: CommandAction, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .frame(width: 20)
                .foregroundStyle(isSelected ? .white : Theme.Colors.secondaryText)
                .font(.system(size: 13))

            Text(action.title)
                .font(Theme.Fonts.sidebarItem)
                .foregroundStyle(isSelected ? .white : .primary)

            if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : Theme.Colors.tertiaryText)
            }

            Spacer()

            Text(action.category)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text("No matching commands")
                .font(Theme.Fonts.sidebarItem)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private let categoryOrder = ["Navigate", "Action", "Terminal", "Cluster"]

    private func dismiss() {
        appState.isCommandPaletteOpen = false
    }
}
