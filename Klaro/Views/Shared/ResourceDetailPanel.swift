import SwiftUI
import CodeEditor

enum ResourceDetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case yaml = "YAML"
    case events = "Events"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "info.circle"
        case .yaml: return "doc.plaintext"
        case .events: return "bell"
        }
    }
}

enum YAMLDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case clean = "Clean"
    case raw = "Raw"

    var id: String { rawValue }
}

struct ResourceDetailPanel: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ResourceDetailViewModel
    @State private var selectedTab: ResourceDetailTab = .overview
    @State private var yamlDisplayMode: YAMLDisplayMode = .clean

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.metadata["name"] ?? "Resource Details")
                    .font(Theme.Fonts.subtitle)
                    .lineLimit(1)

                if let ns = viewModel.metadata["namespace"], !ns.isEmpty {
                    Text(ns)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            Spacer()

            Button {
                appState.isDetailPanelOpen = false
                appState.selectedResourceID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close details panel")
        }
        .padding(Theme.Dimensions.padding)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ResourceDetailTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: ResourceDetailTab) -> some View {
        Button {
            withAnimation(Theme.Animations.tabTransition) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(Theme.Fonts.sidebarItem)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, 8)
            .frame(minHeight: 32, alignment: .center)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(selectedTab == tab ? Theme.Colors.accent.opacity(0.15) : .clear)
            )
            .foregroundStyle(selectedTab == tab ? Theme.Colors.accent : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.Dimensions.smallSpacing)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.isLoading {
            VStack(spacing: Theme.Dimensions.spacing * 2) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading details...")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.failed)
                Text(error)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                switch selectedTab {
                case .overview:
                    overviewTab
                case .yaml:
                    yamlTab
                case .events:
                    eventsTab
                }
            }
            .transition(.opacity)
            .animation(Theme.Animations.tabTransition, value: selectedTab)
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let nodeOverview = viewModel.nodeOverview {
            nodeOverviewTab(nodeOverview)
        } else {
            genericOverviewTab
        }
    }

    private var genericOverviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
                cardSection(title: "Metadata") {
                    ForEach(Array(viewModel.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        detailRow(key: key, value: value)
                    }
                }

                if !viewModel.labels.isEmpty {
                    cardSection(title: "Labels") {
                        ForEach(Array(viewModel.labels.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            labelBadge(key: key, value: value)
                        }
                    }
                }

                if !viewModel.filteredAnnotations.isEmpty {
                    cardSection(title: "Annotations") {
                        ForEach(Array(viewModel.filteredAnnotations.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            detailRow(key: key, value: value)
                        }
                    }
                }
            }
            .padding(Theme.Dimensions.padding)
        }
    }

    private func nodeOverviewTab(_ node: NodeOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
                cardSection(title: "Metrics") {
                    CapacityBar(
                        label: "CPU Requests",
                        used: node.metrics.cpuRequestedCores,
                        total: max(node.metrics.cpuAllocatableCores, node.metrics.cpuCapacityCores),
                        unit: "cores"
                    )
                    CapacityBar(
                        label: "Memory Requests",
                        used: node.metrics.memoryRequestedGiB,
                        total: max(node.metrics.memoryAllocatableGiB, node.metrics.memoryCapacityGiB),
                        unit: "GiB"
                    )
                    CapacityBar(
                        label: "Pods",
                        used: Double(node.metrics.podCount),
                        total: Double(max(node.metrics.podAllocatable, node.metrics.podCapacity)),
                        unit: ""
                    )
                }

                cardSection(title: "Properties") {
                    ForEach(node.properties) { item in
                        detailRow(key: item.key, value: item.value)
                    }
                }

                cardSection(title: "Capacity") {
                    ForEach(node.capacity) { item in
                        detailRow(key: item.name, value: item.value)
                    }
                }

                cardSection(title: "Allocatable") {
                    ForEach(node.allocatable) { item in
                        detailRow(key: item.name, value: item.value)
                    }
                }

                cardSection(title: "Pods") {
                    if node.pods.isEmpty {
                        Text("No pods scheduled on this node.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        nodePodsTable(node.pods)
                    }
                }
            }
            .padding(Theme.Dimensions.padding)
        }
    }

    // MARK: - Card Section

    private func cardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            Text(title)
                .font(Theme.Fonts.sidebarHeader)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
                content()
            }
            .padding(Theme.Dimensions.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                    .fill(Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func detailRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(value.isEmpty ? "-" : value)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func labelBadge(key: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(key)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.accent)
            Text("=")
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(value)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(.primary)
        }
        .textSelection(.enabled)
    }

    private func nodePodsTable(_ pods: [NodePodItem]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Dimensions.spacing) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Namespace")
                    .frame(width: 110, alignment: .leading)
                Text("Ready")
                    .frame(width: 50, alignment: .leading)
                Text("CPU")
                    .frame(width: 60, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .leading)
                Text("Status")
                    .frame(width: 80, alignment: .leading)
            }
            .font(Theme.Fonts.tableHeader)
            .foregroundStyle(Theme.Colors.secondaryText)
            .padding(.vertical, Theme.Dimensions.smallSpacing)

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(pods) { pod in
                    HStack(spacing: Theme.Dimensions.spacing) {
                        Text(pod.name)
                            .font(Theme.Fonts.tableCell)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(pod.namespace)
                            .font(Theme.Fonts.tableCell)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)

                        Text(pod.ready)
                            .font(Theme.Fonts.monoSmall)
                            .frame(width: 50, alignment: .leading)

                        Text(pod.cpu)
                            .font(Theme.Fonts.monoSmall)
                            .frame(width: 60, alignment: .leading)

                        Text(pod.memory)
                            .font(Theme.Fonts.monoSmall)
                            .frame(width: 70, alignment: .leading)

                        Text(pod.status)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.forStatus(pod.status))
                            .frame(width: 80, alignment: .leading)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
    }

    // MARK: - YAML Tab

    @ViewBuilder
    private var yamlTab: some View {
        let displayedYAML = yamlDisplayMode == .clean ? viewModel.cleanResourceYAML : viewModel.resourceYAML

        VStack(spacing: 0) {
            HStack {
                Picker("YAML Mode", selection: $yamlDisplayMode) {
                    ForEach(YAMLDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Spacer()
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.smallSpacing)

            Divider()

            if displayedYAML.isEmpty {
                VStack(spacing: Theme.Dimensions.spacing) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                    Text("No YAML available")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeEditor(
                    source: .constant(displayedYAML),
                    language: .yaml,
                    theme: .ocean,
                    flags: [.selectable],
                    indentStyle: .softTab(width: 2)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Events Tab

    private var eventsTab: some View {
        Group {
            if viewModel.events.isEmpty {
                VStack(spacing: Theme.Dimensions.spacing) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                    Text("No events")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.events) { event in
                            eventRow(event)
                                .padding(.horizontal, Theme.Dimensions.padding)
                                .padding(.vertical, Theme.Dimensions.spacing)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: ResourceItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
            HStack {
                StatusBadge(status: event.status)

                Text(event.extraColumns["reason"] ?? "")
                    .font(Theme.Fonts.tableCell)
                    .foregroundStyle(.primary)

                Spacer()

                if let age = event.age {
                    AgeLabel(date: age)
                }
            }

            Text(event.extraColumns["message"] ?? "")
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(3)

            if let count = event.extraColumns["count"], count != "0" {
                Text("Count: \(count)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }
}
