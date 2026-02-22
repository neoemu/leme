import SwiftUI

struct ResourceTableColumn: Sendable {
    let title: String
    let key: String
    let minWidth: CGFloat
    let idealWidth: CGFloat?
    let sortField: SortField?

    /// Flexible column (expands to fill available space).
    init(title: String, key: String, sortField: SortField? = nil) {
        self.title = title
        self.key = key
        self.minWidth = 80
        self.idealWidth = nil
        self.sortField = sortField
    }

    /// Fixed-initial-width column that can still be resized.
    init(title: String, key: String, width: CGFloat, sortField: SortField? = nil) {
        self.title = title
        self.key = key
        self.minWidth = max(40, width * 0.5)
        self.idealWidth = width
        self.sortField = sortField
    }

    /// Whether this column should flex to fill remaining space.
    var isFlexible: Bool { idealWidth == nil }
}

struct ResourceTableView: View {
    @Environment(AppState.self) private var appState
    let columns: [ResourceTableColumn]
    @Bindable var viewModel: ResourceListViewModel
    var onViewLogs: ((ResourceItem) -> Void)?
    var onShell: ((ResourceItem) -> Void)?
    var onViewYAML: ((ResourceItem) -> Void)?
    var onDelete: ((ResourceItem) -> Void)?
    /// Optional custom cell renderer. Return a view for custom rendering, or nil for default.
    var customCellRenderer: ((ResourceTableColumn, ResourceItem) -> AnyView?)?
    /// Optional namespace grouping header renderer.
    var groupByNamespace: Bool = false

    /// Tracks each column's current width. Initialized from column definitions.
    @State private var columnWidths: [CGFloat] = []
    /// Snapshot of column widths at drag start, used to compute correct deltas.
    @State private var dragStartWidths: [CGFloat] = []
    /// Tracks the total available width for the table area.
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            tableContent
        }
        .onAppear {
            initializeColumnWidths()
        }
        .onChange(of: columns.count) { _, _ in
            initializeColumnWidths()
        }
    }

    // MARK: - Column Width Management

    private func initializeColumnWidths() {
        guard columnWidths.isEmpty || columnWidths.count != columns.count else { return }
        columnWidths = columns.map { $0.idealWidth ?? 200 }
    }

    /// Returns the width for a column at the given index, accounting for flexible columns.
    private func effectiveWidth(at index: Int) -> CGFloat {
        guard index < columnWidths.count else { return 100 }
        let col = columns[index]
        if col.isFlexible {
            let fixedTotal = columns.enumerated()
                .filter { !$0.element.isFlexible }
                .reduce(CGFloat(0)) { sum, pair in
                    sum + (pair.offset < columnWidths.count ? columnWidths[pair.offset] : 0)
                }
            let horizontalPadding = Theme.Dimensions.padding * 2
            let dragHandlesWidth = CGFloat(columns.count - 1) * 8
            let remaining = availableWidth - fixedTotal - horizontalPadding - dragHandlesWidth
            return max(col.minWidth, remaining)
        }
        return max(col.minWidth, columnWidths[index])
    }

    /// Total content width including all columns + padding + drag handles.
    private var totalContentWidth: CGFloat {
        let horizontalPadding = Theme.Dimensions.padding * 2
        let dragHandlesWidth = CGFloat(columns.count - 1) * 8
        let columnTotal = columns.indices.reduce(CGFloat(0)) { sum, idx in
            sum + effectiveWidth(at: idx)
        }
        return columnTotal + horizontalPadding + dragHandlesWidth
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
        GeometryReader { geometry in
            let contentWidth = totalContentWidth
            let needsHorizontalScroll = contentWidth > geometry.size.width

            ScrollView(needsHorizontalScroll ? [.horizontal, .vertical] : [.vertical], showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                        .frame(width: needsHorizontalScroll ? contentWidth : nil)
                    Divider()

                    if groupByNamespace {
                        groupedContent(contentWidth: needsHorizontalScroll ? contentWidth : nil)
                    } else {
                        flatContent(contentWidth: needsHorizontalScroll ? contentWidth : nil)
                    }
                }
            }
            .onAppear {
                availableWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                availableWidth = newWidth
            }
        }
    }

    private func flatContent(contentWidth: CGFloat?) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredResources) { resource in
                resourceRow(resource)
                    .frame(width: contentWidth)
                Divider()
                    .padding(.leading, Theme.Dimensions.padding)
            }
        }
    }

    private func groupedContent(contentWidth: CGFloat?) -> some View {
        let grouped = Dictionary(grouping: viewModel.filteredResources) { $0.namespace ?? "default" }
        let sortedNamespaces = grouped.keys.sorted()

        return LazyVStack(spacing: 0) {
            ForEach(sortedNamespaces, id: \.self) { namespace in
                // Namespace header
                HStack {
                    Text("Namespace:")
                        .font(Theme.Fonts.sidebarHeader)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(namespace)
                        .font(Theme.Fonts.subtitle)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.smallSpacing)
                .background(Color.secondary.opacity(0.05))
                .frame(width: contentWidth)

                // Resources in this namespace
                ForEach(grouped[namespace] ?? []) { resource in
                    resourceRow(resource)
                        .frame(width: contentWidth)
                    Divider()
                        .padding(.leading, Theme.Dimensions.padding)
                }
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                headerCell(column, at: index)

                if index < columns.count - 1 {
                    columnResizeHandle(at: index)
                }
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.smallSpacing)
        .background(Color.secondary.opacity(0.05))
    }

    private func headerCell(_ column: ResourceTableColumn, at index: Int) -> some View {
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
        .frame(width: effectiveWidth(at: index), alignment: .leading)
    }

    // MARK: - Column Resize Handle

    private func columnResizeHandle(at index: Int) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8, height: 16)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Theme.Colors.separator.opacity(0.3))
                    .frame(width: 1)
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidths.isEmpty {
                            dragStartWidths = columnWidths
                        }
                        guard index < dragStartWidths.count else { return }
                        let delta = value.translation.width

                        let col = columns[index]
                        if !col.isFlexible {
                            columnWidths[index] = max(col.minWidth, dragStartWidths[index] + delta)
                        }
                        let nextIndex = index + 1
                        if nextIndex < columns.count, !columns[nextIndex].isFlexible,
                           nextIndex < dragStartWidths.count {
                            let nextCol = columns[nextIndex]
                            columnWidths[nextIndex] = max(nextCol.minWidth, dragStartWidths[nextIndex] - delta)
                        }
                    }
                    .onEnded { _ in
                        dragStartWidths = []
                    }
            )
    }

    // MARK: - Data Rows

    private func resourceRow(_ resource: ResourceItem) -> some View {
        let isSelected = appState.selectedResourceID == resource.id

        return HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                cellContent(for: column, at: index, resource: resource)

                if index < columns.count - 1 {
                    Spacer()
                        .frame(width: 8)
                }
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
    private func cellContent(for column: ResourceTableColumn, at index: Int, resource: ResourceItem) -> some View {
        // Check custom renderer first
        if let customRenderer = customCellRenderer,
           let customView = customRenderer(column, resource) {
            customView
                .frame(width: effectiveWidth(at: index), alignment: .leading)
        } else {
            defaultCellContent(for: column, resource: resource)
                .frame(width: effectiveWidth(at: index), alignment: .leading)
        }
    }

    @ViewBuilder
    private func defaultCellContent(for column: ResourceTableColumn, resource: ResourceItem) -> some View {
        let content: String = {
            switch column.key {
            case "name":
                return resource.name
            case "namespace":
                return resource.namespace ?? ""
            case "status":
                return resource.status
            case "age":
                return ""
            default:
                return resource.extraColumns[column.key] ?? ""
            }
        }()

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
                .truncationMode(.middle)
        }
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
