import SwiftUI

struct ResourceTableColumn: Sendable {
    let title: String
    let key: String
    let width: CGFloat?
    let sortField: SortField?

    init(title: String, key: String, width: CGFloat? = nil, sortField: SortField? = nil) {
        self.title = title
        self.key = key
        self.width = width
        self.sortField = sortField
    }
}

struct ResourceTableView: View {
    @Environment(AppState.self) private var appState
    let columns: [ResourceTableColumn]
    @Bindable var viewModel: ResourceListViewModel
    var onViewLogs: ((ResourceItem) -> Void)?
    var onShell: ((ResourceItem) -> Void)?
    var onViewYAML: ((ResourceItem) -> Void)?
    var onDelete: ((ResourceItem) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            tableContent
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.secondaryText)

            TextField("Search resources...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.tableCell)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(viewModel.filteredResources.count) items")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.spacing)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        if viewModel.isLoading && viewModel.resources.isEmpty {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else if viewModel.filteredResources.isEmpty {
            emptyView
        } else {
            tableView
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            ProgressView()
                .controlSize(.small)
            Text("Loading resources...")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Colors.failed)
            Text("Error loading resources")
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        EmptyStateView(
            icon: "tray",
            title: "No Resources Found",
            message: viewModel.searchText.isEmpty
                ? "No resources in this namespace."
                : "No resources matching '\(viewModel.searchText)'."
        )
    }

    // MARK: - Table

    private var tableView: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredResources) { resource in
                        resourceRow(resource)
                        Divider()
                            .padding(.leading, Theme.Dimensions.padding)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                headerCell(column)
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.smallSpacing)
        .background(Color.secondary.opacity(0.05))
    }

    private func headerCell(_ column: ResourceTableColumn) -> some View {
        let isSorted = column.sortField == viewModel.sortField

        return Button {
            if let sortField = column.sortField {
                viewModel.toggleSort(field: sortField)
            }
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Text(column.title.uppercased())
                    .font(Theme.Fonts.tableHeader)
                    .foregroundStyle(isSorted ? .primary : Theme.Colors.secondaryText)

                if isSorted {
                    Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Colors.accent)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .frame(width: column.width)
        .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
    }

    private func resourceRow(_ resource: ResourceItem) -> some View {
        let isSelected = appState.selectedResourceID == resource.id

        return HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                cellContent(for: column, resource: resource)
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .frame(height: Theme.Dimensions.tableRowHeight)
        .background(isSelected ? Theme.Colors.accent.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectResource(resource.id)
        }
        .contextMenu {
            contextMenuItems(for: resource)
        }
    }

    @ViewBuilder
    private func cellContent(for column: ResourceTableColumn, resource: ResourceItem) -> some View {
        let content: String = {
            switch column.key {
            case "name":
                return resource.name
            case "namespace":
                return resource.namespace ?? ""
            case "status":
                return resource.status
            case "age":
                return "" // handled specially
            default:
                return resource.extraColumns[column.key] ?? ""
            }
        }()

        Group {
            if column.key == "status" {
                StatusBadge(status: resource.status)
            } else if column.key == "age" {
                if let date = resource.age {
                    AgeLabel(date: date)
                } else {
                    Text("-")
                        .font(Theme.Fonts.tableCell)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            } else {
                Text(content)
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(column.key == "name" ? .primary : Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: column.width, alignment: .leading)
        .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: .leading)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for resource: ResourceItem) -> some View {
        if let onViewLogs {
            Button {
                onViewLogs(resource)
            } label: {
                Label("View Logs", systemImage: "doc.text.magnifyingglass")
            }
        }

        if let onShell {
            Button {
                onShell(resource)
            } label: {
                Label("Shell", systemImage: "terminal")
            }
        }

        if let onViewYAML {
            Button {
                onViewYAML(resource)
            } label: {
                Label("View YAML", systemImage: "doc.plaintext")
            }
        }

        if onViewLogs != nil || onShell != nil || onViewYAML != nil {
            Divider()
        }

        if let onDelete {
            Button(role: .destructive) {
                onDelete(resource)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
