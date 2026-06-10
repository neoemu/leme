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

/// An extra, caller-defined row action exposed in both the context menu and
/// the "..." actions menu (kept in sync per the UI consistency contract).
struct ResourceRowAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var needsConfirmation: Bool = false
    var confirmationMessage: String = ""
    let handler: () -> Void
}

struct ResourceTableView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settingsStore
    let columns: [ResourceTableColumn]
    @Bindable var viewModel: ResourceListViewModel
    var onViewLogs: ((ResourceItem) -> Void)?
    var onShell: ((ResourceItem) -> Void)?
    var onViewYAML: ((ResourceItem) -> Void)?
    var onDelete: ((ResourceItem) -> Void)?
    var onScale: ((ResourceItem, Int) -> Void)?
    var onRestart: ((ResourceItem) -> Void)?
    var onDownloadYAML: ((ResourceItem) -> Void)?
    var extraActions: ((ResourceItem) -> [ResourceRowAction])?
    var deleteConfirmationMessageBuilder: ((ResourceItem) -> String)? = nil
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

    // Delete confirmation
    @State private var resourceToDelete: ResourceItem?
    @State private var showDeleteConfirmation = false

    // Scale sheet
    @State private var resourceToScale: ResourceItem?
    @State private var desiredReplicas: Int = 1

    // Restart confirmation
    @State private var resourceToRestart: ResourceItem?
    @State private var showRestartConfirmation = false

    // Extra action confirmation
    @State private var pendingConfirmAction: ResourceRowAction?
    @State private var showActionConfirmation = false

    // Production type-to-confirm
    @State private var dangerAction: PendingDangerAction?

    private var isProductionCluster: Bool {
        settingsStore.isProduction(appState.activeCluster)
    }

    /// Width of the fixed actions column ("..." button).
    private let actionsColumnWidth: CGFloat = 36

    /// Whether this table has any action callbacks configured.
    private var hasActions: Bool {
        onViewLogs != nil || onShell != nil || onViewYAML != nil ||
        onDelete != nil || onScale != nil || onRestart != nil || onDownloadYAML != nil ||
        extraActions != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if case .idle = viewModel.operationState {
                EmptyView()
            } else {
                operationBanner
            }
            Divider()
            tableContent
        }
        .onAppear {
            initializeColumnWidths()
        }
        .onChange(of: columns.count) { _, _ in
            initializeColumnWidths()
        }
        .onDisappear {
            viewModel.stopWatch()
        }
        .confirmationDialog(
            "Delete \(resourceToDelete?.name ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let resource = resourceToDelete {
                    onDelete?(resource)
                }
                resourceToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                resourceToDelete = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .confirmationDialog(
            "Restart \(resourceToRestart?.name ?? "")?",
            isPresented: $showRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restart", role: .destructive) {
                if let resource = resourceToRestart {
                    onRestart?(resource)
                }
                resourceToRestart = nil
            }
            Button("Cancel", role: .cancel) {
                resourceToRestart = nil
            }
        } message: {
            Text("This will trigger a rolling restart of all pods.")
        }
        .confirmationDialog(
            pendingConfirmAction?.title ?? "",
            isPresented: $showActionConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                pendingConfirmAction?.title ?? "Confirm",
                role: pendingConfirmAction?.isDestructive == true ? .destructive : nil
            ) {
                pendingConfirmAction?.handler()
                pendingConfirmAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingConfirmAction = nil
            }
        } message: {
            Text(pendingConfirmAction?.confirmationMessage ?? "")
        }
        .sheet(item: $dangerAction) { action in
            DangerConfirmationSheet(
                action: action,
                clusterName: appState.activeCluster?.displayName ?? ""
            ) {
                dangerAction = nil
            }
        }
        .sheet(item: $resourceToScale) { resource in
            ScaleSheetView(
                resourceName: resource.name,
                replicas: $desiredReplicas
            ) {
                onScale?(resource, desiredReplicas)
                resourceToScale = nil
            } onCancel: {
                resourceToScale = nil
            }
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
            let actionsWidth = hasActions ? actionsColumnWidth + 8 : 0
            let remaining = availableWidth - fixedTotal - horizontalPadding - dragHandlesWidth - actionsWidth
            return max(col.minWidth, remaining)
        }
        return max(col.minWidth, columnWidths[index])
    }

    /// Total content width including all columns + padding + drag handles + actions column.
    private var totalContentWidth: CGFloat {
        let horizontalPadding = Theme.Dimensions.padding * 2
        let dragHandlesWidth = CGFloat(columns.count - 1) * 8
        let columnTotal = columns.indices.reduce(CGFloat(0)) { sum, idx in
            sum + effectiveWidth(at: idx)
        }
        let actionsWidth = hasActions ? actionsColumnWidth + 8 : 0
        return columnTotal + horizontalPadding + dragHandlesWidth + actionsWidth
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

            if viewModel.hasLiveWatch {
                liveWatchStatusView
            }

            Text("\(viewModel.filteredResources.count) items")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.spacing)
    }

    private var deleteConfirmationMessage: String {
        guard let resource = resourceToDelete else {
            return "This action cannot be undone."
        }

        if let deleteConfirmationMessageBuilder {
            return deleteConfirmationMessageBuilder(resource)
        }

        let namespace = resource.namespace ?? "cluster-scoped"
        return "Resource: \(resource.kind.rawValue)\nNamespace: \(namespace)\nName: \(resource.name)\n\nThis action cannot be undone."
    }

    @ViewBuilder
    private var operationBanner: some View {
        switch viewModel.operationState {
        case .idle:
            EmptyView()
        case .running(let message):
            bannerRow(
                icon: AnyView(ProgressView().controlSize(.small)),
                message: message,
                textColor: Theme.Colors.secondaryText,
                background: Theme.Colors.cardBackground
            )
        case .success(let message):
            bannerRow(
                icon: AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.running)),
                message: message,
                textColor: Theme.Colors.secondaryText,
                background: Theme.Colors.successBackground
            )
        case .error(let message):
            bannerRow(
                icon: AnyView(Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.failed)),
                message: message,
                textColor: Theme.Colors.failed,
                background: Theme.Colors.errorBackground,
                dismissible: true
            )
        }
    }

    private func bannerRow(
        icon: AnyView,
        message: String,
        textColor: Color,
        background: Color,
        dismissible: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            icon
            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(textColor)
                .lineLimit(2)
            Spacer()
            if dismissible {
                Button {
                    viewModel.clearOperationState()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.smallSpacing)
        .background(background)
    }

    private var liveWatchStatusView: some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            Circle()
                .fill(watchStatusColor)
                .frame(width: 7, height: 7)
            Text(viewModel.liveWatchStatusText)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Theme.Colors.cardBackground)
        )
    }

    private var watchStatusColor: Color {
        switch viewModel.liveWatchStatus {
        case .off:
            return Theme.Colors.tertiaryText
        case .syncing:
            return Theme.Colors.pending
        case .live:
            return Theme.Colors.running
        case .recovering:
            return Theme.Colors.warning
        }
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
                // Two-axis ScrollViews center content smaller than the viewport;
                // pin it to the top so short result sets don't float mid-screen.
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
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
                    .id(rowIdentity(resource))
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
                        .id(rowIdentity(resource))
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

            if hasActions {
                Spacer().frame(width: 8)
                Spacer().frame(width: actionsColumnWidth)
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

            if hasActions {
                Spacer().frame(width: 8)
                actionsMenuButton(for: resource)
                    .frame(width: actionsColumnWidth)
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .frame(height: Theme.Dimensions.tableRowHeight)
        .background(isSelected ? Theme.Colors.tableSelectionBackground : .clear)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    appState.showResourceDetail(resource.id)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    appState.selectResource(resource.id)
                }
        )
        .contextMenu {
            Button {
                appState.showResourceDetail(resource.id)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

            contextMenuItems(for: resource)
        }
    }

    // MARK: - Actions Menu Button ("...")

    private func actionsMenuButton(for resource: ResourceItem) -> some View {
        Menu {
            Button {
                appState.showResourceDetail(resource.id)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

            contextMenuItems(for: resource)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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

    private func rowIdentity(_ resource: ResourceItem) -> String {
        let extrasSignature = resource.extraColumns
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")

        return [
            resource.id,
            resource.status,
            resource.namespace ?? "",
            extrasSignature,
        ].joined(separator: "||")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for resource: ResourceItem) -> some View {
        // --- Interactive actions ---
        if let onShell {
            Button {
                onShell(resource)
            } label: {
                Label("Execute Shell", systemImage: "terminal")
            }
        }

        if let onViewLogs {
            Button {
                onViewLogs(resource)
            } label: {
                Label("View Logs", systemImage: "doc.text.magnifyingglass")
            }
        }

        if onScale != nil {
            Button {
                // Parse current replicas from "ready/total" format
                if let readyStr = resource.extraColumns["ready"],
                   let slashIndex = readyStr.firstIndex(of: "/") {
                    let totalStr = readyStr[readyStr.index(after: slashIndex)...]
                    desiredReplicas = Int(totalStr) ?? 1
                } else if let desiredStr = resource.extraColumns["desired"] {
                    desiredReplicas = Int(desiredStr) ?? 1
                } else {
                    desiredReplicas = 1
                }
                resourceToScale = resource
            } label: {
                Label("Scale...", systemImage: "arrow.up.arrow.down")
            }
        }

        if onRestart != nil {
            Button {
                if isProductionCluster {
                    dangerAction = PendingDangerAction(
                        title: "Restart \(resource.name)",
                        message: "This triggers a rolling restart of all pods of \(resource.name) on a production cluster.",
                        confirmText: resource.name,
                        confirmLabel: "Restart"
                    ) {
                        onRestart?(resource)
                    }
                } else {
                    resourceToRestart = resource
                    showRestartConfirmation = true
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        }

        if let extraActions {
            let actions = extraActions(resource)
            ForEach(actions) { action in
                Button(role: action.isDestructive ? .destructive : nil) {
                    if action.needsConfirmation && action.isDestructive && isProductionCluster {
                        dangerAction = PendingDangerAction(
                            title: action.title.trimmingCharacters(in: CharacterSet(charactersIn: "…")),
                            message: action.confirmationMessage,
                            confirmText: resource.name,
                            confirmLabel: "Confirm",
                            handler: action.handler
                        )
                    } else if action.needsConfirmation {
                        pendingConfirmAction = action
                        showActionConfirmation = true
                    } else {
                        action.handler()
                    }
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
            }
        }

        if onShell != nil || onViewLogs != nil || onScale != nil || onRestart != nil || extraActions != nil {
            Divider()
        }

        // --- Edit / inspect actions ---
        if let onViewYAML {
            Button {
                onViewYAML(resource)
            } label: {
                Label("Edit YAML", systemImage: "doc.plaintext")
            }
        }

        if let onDownloadYAML {
            Button {
                onDownloadYAML(resource)
            } label: {
                Label("Download YAML", systemImage: "arrow.down.doc")
            }
        }

        if onViewYAML != nil || onDownloadYAML != nil {
            Divider()
        }

        // --- Destructive actions ---
        if onDelete != nil {
            Button(role: .destructive) {
                if isProductionCluster {
                    dangerAction = PendingDangerAction(
                        title: "Delete \(resource.name)",
                        message: deleteConfirmationMessageBuilder?(resource)
                            ?? "This permanently deletes \(resource.kind.rawValue) \(resource.name) from a production cluster.",
                        confirmText: resource.name,
                        confirmLabel: "Delete"
                    ) {
                        onDelete?(resource)
                    }
                } else {
                    resourceToDelete = resource
                    showDeleteConfirmation = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Scale Sheet

private struct ScaleSheetView: View {
    let resourceName: String
    @Binding var replicas: Int
    let onScale: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Scale \(resourceName)")
                .font(.headline)

            HStack {
                Text("Replicas:")
                TextField("", value: $replicas, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Stepper("", value: $replicas, in: 0...100)
                    .labelsHidden()
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Scale") {
                    onScale()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}
