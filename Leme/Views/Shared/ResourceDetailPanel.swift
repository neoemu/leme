import AppKit
import SwiftUI
import CodeEditor
import Foundation

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

enum NodeMetricsViewMode: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case disk

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        }
    }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        }
    }
}

struct ResourceDetailPanel: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ResourceDetailViewModel
    @State private var selectedTab: ResourceDetailTab = .overview
    @State private var yamlDisplayMode: YAMLDisplayMode = .clean
    @State private var nodeMetricsMode: NodeMetricsViewMode = .cpu
    @State private var revealedSecretKeys: Set<String> = []
    @State private var copiedSecretKey: String?

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
                    .fill(selectedTab == tab ? Color.primary.opacity(0.09) : .clear)
            )
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
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

                if !viewModel.secretData.isEmpty {
                    cardSection(title: "Data (\(viewModel.secretType))") {
                        ForEach(Array(viewModel.secretData.sorted(by: { $0.key < $1.key })), id: \.key) { key, encodedValue in
                            secretDataRow(key: key, encodedValue: encodedValue)
                        }
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
                    nodeMetricsModeToolbar
                    nodeMetricsLegend(for: nodeMetricsMode)

                    if !viewModel.nodeMetricsHistory.isEmpty {
                        nodeMetricsChart(points: viewModel.nodeMetricsHistory, mode: nodeMetricsMode)
                            .frame(height: 150)
                    }

                    Text(nodeMetricsSourceText(node.metrics))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(node.metrics.metricsAvailable ? Theme.Colors.secondaryText : Theme.Colors.tertiaryText)

                    nodeMetricsSummary(for: node.metrics, mode: nodeMetricsMode)
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

    // MARK: - Secret Data Row

    private func secretDataRow(key: String, encodedValue: String) -> some View {
        let isRevealed = revealedSecretKeys.contains(key)
        let decodedValue = Self.decodeBase64(encodedValue)

        return VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Text(key)
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: Theme.Dimensions.smallSpacing)

                Button {
                    if isRevealed {
                        revealedSecretKeys.remove(key)
                    } else {
                        revealedSecretKeys.insert(key)
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide value" : "Reveal decoded value")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(decodedValue ?? encodedValue, forType: .string)
                    withAnimation(Theme.Animations.hoverTransition) {
                        copiedSecretKey = key
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if copiedSecretKey == key {
                            withAnimation(Theme.Animations.hoverTransition) {
                                copiedSecretKey = nil
                            }
                        }
                    }
                } label: {
                    Image(systemName: copiedSecretKey == key ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedSecretKey == key ? Theme.Colors.running : Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(copiedSecretKey == key ? "Copied!" : "Copy decoded value")
            }

            if isRevealed {
                Text(decodedValue ?? "<binary data — \(encodedValue.count) base64 chars>")
                    .font(Theme.Fonts.monoSmall)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Dimensions.smallSpacing)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                            .fill(Color.primary.opacity(0.05))
                    )
            } else {
                Text(String(repeating: "•", count: min(max(decodedValue?.count ?? 8, 4), 24)))
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    private static func decodeBase64(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
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
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
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
                .foregroundStyle(Theme.Colors.secondaryText)
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

    private struct NodeMetricSeries: Identifiable {
        let id: String
        let label: String
        let color: Color
        let values: [Double?]
        let lineWidth: CGFloat
    }

    private var nodeMetricsModeToolbar: some View {
        HStack(spacing: 6) {
            ForEach(NodeMetricsViewMode.allCases) { mode in
                Button {
                    withAnimation(Theme.Animations.tabTransition) {
                        nodeMetricsMode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(nodeMetricsMode == mode ? Color.primary.opacity(0.10) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.primary.opacity(nodeMetricsMode == mode ? 0.16 : 0.07), lineWidth: 1)
                        )
                        .foregroundStyle(nodeMetricsMode == mode ? .primary : Theme.Colors.secondaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func nodeMetricsLegend(for mode: NodeMetricsViewMode) -> some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            switch mode {
            case .cpu:
                legendItem(label: "CPU Usage", color: Color(red: 0.16, green: 0.70, blue: 0.96))
                legendItem(label: "CPU Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45))
                legendItem(label: "CPU Allocatable", color: Color(red: 0.56, green: 0.66, blue: 0.98))
                legendItem(label: "CPU Capacity", color: Theme.Colors.tertiaryText)
            case .memory:
                legendItem(label: "Memory Usage", color: Color(red: 0.82, green: 0.28, blue: 0.84))
                legendItem(label: "Memory Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45))
                legendItem(label: "Memory Allocatable", color: Color(red: 0.24, green: 0.45, blue: 0.86))
                legendItem(label: "Memory Capacity", color: Theme.Colors.tertiaryText)
            case .network:
                legendItem(label: "Receive", color: Color(red: 0.22, green: 0.77, blue: 0.94))
                legendItem(label: "Transmit", color: Color(red: 0.68, green: 0.41, blue: 0.93))
            case .disk:
                legendItem(label: "Disk Usage", color: Color(red: 0.95, green: 0.74, blue: 0.24))
                legendItem(label: "Disk Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45))
                legendItem(label: "Disk Allocatable", color: Color(red: 0.24, green: 0.45, blue: 0.86))
                legendItem(label: "Disk Capacity", color: Theme.Colors.tertiaryText)
            }
            Spacer()
        }
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private func nodeMetricsSourceText(_ metrics: NodeMetricSummary) -> String {
        guard metrics.metricsAvailable else {
            return "Live usage unavailable. Showing requested and capacity values."
        }
        guard let timestamp = metrics.metricsTimestamp else {
            return "Live usage from metrics.k8s.io / kubelet summary"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return "Live usage from metrics.k8s.io / kubelet summary • updated \(formatter.string(from: timestamp))"
    }

    private func nodeMetricsChart(points: [NodeMetricsHistoryPoint], mode: NodeMetricsViewMode) -> some View {
        let series = nodeMetricSeries(for: mode, points: points)
        let maxValue = max(1.0, series.flatMap { $0.values.compactMap { $0 } }.max() ?? 1.0)

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { idx in
                        Divider()
                            .overlay(Theme.Colors.separator.opacity(idx == 0 ? 0.35 : 0.22))
                        if idx < 4 { Spacer() }
                    }
                }

                ForEach(series.indices, id: \.self) { idx in
                    linePath(values: series[idx].values, in: geometry.size, maxValue: maxValue)
                        .stroke(series[idx].color, style: StrokeStyle(lineWidth: series[idx].lineWidth))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(nodeMetricYAxisTitle(for: mode))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("max \(nodeMetricMaxValueText(maxValue, mode: mode))")
                        .font(Theme.Fonts.monoSmall)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
                .padding(6)
            }
        }
    }

    private func nodeMetricSeries(for mode: NodeMetricsViewMode, points: [NodeMetricsHistoryPoint]) -> [NodeMetricSeries] {
        switch mode {
        case .cpu:
            return [
                NodeMetricSeries(id: "cpu-capacity", label: "CPU Capacity", color: Theme.Colors.tertiaryText.opacity(0.85), values: points.map { Optional($0.cpuCapacityCores) }, lineWidth: 1.2),
                NodeMetricSeries(id: "cpu-allocatable", label: "CPU Allocatable", color: Color(red: 0.56, green: 0.66, blue: 0.98), values: points.map { Optional($0.cpuAllocatableCores) }, lineWidth: 1.4),
                NodeMetricSeries(id: "cpu-requests", label: "CPU Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45), values: points.map { Optional($0.cpuRequestedCores) }, lineWidth: 1.6),
                NodeMetricSeries(id: "cpu-usage", label: "CPU Usage", color: Color(red: 0.16, green: 0.70, blue: 0.96), values: points.map(\.cpuUsageCores), lineWidth: 1.8),
            ]
        case .memory:
            return [
                NodeMetricSeries(id: "memory-capacity", label: "Memory Capacity", color: Theme.Colors.tertiaryText.opacity(0.85), values: points.map { Optional($0.memoryCapacityGiB) }, lineWidth: 1.2),
                NodeMetricSeries(id: "memory-allocatable", label: "Memory Allocatable", color: Color(red: 0.24, green: 0.45, blue: 0.86), values: points.map { Optional($0.memoryAllocatableGiB) }, lineWidth: 1.4),
                NodeMetricSeries(id: "memory-requests", label: "Memory Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45), values: points.map { Optional($0.memoryRequestedGiB) }, lineWidth: 1.6),
                NodeMetricSeries(id: "memory-usage", label: "Memory Usage", color: Color(red: 0.82, green: 0.28, blue: 0.84), values: points.map(\.memoryUsageGiB), lineWidth: 1.8),
            ]
        case .network:
            return [
                NodeMetricSeries(id: "network-rx", label: "Receive", color: Color(red: 0.22, green: 0.77, blue: 0.94), values: points.map(\.networkRxBytesPerSecond), lineWidth: 1.8),
                NodeMetricSeries(id: "network-tx", label: "Transmit", color: Color(red: 0.68, green: 0.41, blue: 0.93), values: points.map(\.networkTxBytesPerSecond), lineWidth: 1.8),
            ]
        case .disk:
            return [
                NodeMetricSeries(id: "disk-capacity", label: "Disk Capacity", color: Theme.Colors.tertiaryText.opacity(0.85), values: points.map { Optional($0.diskCapacityGiB) }, lineWidth: 1.2),
                NodeMetricSeries(id: "disk-allocatable", label: "Disk Allocatable", color: Color(red: 0.24, green: 0.45, blue: 0.86), values: points.map { Optional($0.diskAllocatableGiB) }, lineWidth: 1.4),
                NodeMetricSeries(id: "disk-requests", label: "Disk Requests", color: Color(red: 0.20, green: 0.82, blue: 0.45), values: points.map { Optional($0.diskRequestedGiB) }, lineWidth: 1.6),
                NodeMetricSeries(id: "disk-usage", label: "Disk Usage", color: Color(red: 0.95, green: 0.74, blue: 0.24), values: points.map(\.diskUsageGiB), lineWidth: 1.8),
            ]
        }
    }

    private func nodeMetricYAxisTitle(for mode: NodeMetricsViewMode) -> String {
        switch mode {
        case .cpu:
            return "CPU Cores"
        case .memory, .disk:
            return "GiB"
        case .network:
            return "Bytes/s"
        }
    }

    private func nodeMetricMaxValueText(_ value: Double, mode: NodeMetricsViewMode) -> String {
        switch mode {
        case .cpu:
            return String(format: "%.2f", value)
        case .memory, .disk:
            return String(format: "%.1f GiB", value)
        case .network:
            return formatByteRate(value)
        }
    }

    @ViewBuilder
    private func nodeMetricsSummary(for metrics: NodeMetricSummary, mode: NodeMetricsViewMode) -> some View {
        switch mode {
        case .cpu:
            if let cpuUsage = metrics.cpuUsageCores {
                CapacityBar(
                    label: "CPU Usage",
                    used: cpuUsage,
                    total: max(metrics.cpuAllocatableCores, metrics.cpuCapacityCores),
                    unit: "cores"
                )
            }
            CapacityBar(
                label: "CPU Requests",
                used: metrics.cpuRequestedCores,
                total: max(metrics.cpuAllocatableCores, metrics.cpuCapacityCores),
                unit: "cores"
            )
            CapacityBar(
                label: "Pods",
                used: Double(metrics.podCount),
                total: Double(max(metrics.podAllocatable, metrics.podCapacity)),
                unit: ""
            )

        case .memory:
            if let memoryUsage = metrics.memoryUsageGiB {
                CapacityBar(
                    label: "Memory Usage",
                    used: memoryUsage,
                    total: max(metrics.memoryAllocatableGiB, metrics.memoryCapacityGiB),
                    unit: "GiB"
                )
            }
            CapacityBar(
                label: "Memory Requests",
                used: metrics.memoryRequestedGiB,
                total: max(metrics.memoryAllocatableGiB, metrics.memoryCapacityGiB),
                unit: "GiB"
            )

        case .network:
            metricValueRow(label: "Receive", value: metrics.networkRxBytesPerSecond.map(formatByteRate) ?? "-")
            metricValueRow(label: "Transmit", value: metrics.networkTxBytesPerSecond.map(formatByteRate) ?? "-")
            if metrics.networkRxBytesPerSecond == nil && metrics.networkTxBytesPerSecond == nil {
                Text("Network throughput appears after a couple of samples.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

        case .disk:
            if let diskUsage = metrics.diskUsageGiB {
                CapacityBar(
                    label: "Disk Usage",
                    used: diskUsage,
                    total: max(metrics.diskAllocatableGiB, metrics.diskCapacityGiB),
                    unit: "GiB"
                )
            }
            CapacityBar(
                label: "Disk Requests",
                used: metrics.diskRequestedGiB,
                total: max(metrics.diskAllocatableGiB, metrics.diskCapacityGiB),
                unit: "GiB"
            )
        }
    }

    private func metricValueRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(Theme.Fonts.monoMedium)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private func formatByteRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.2f GiB/s", bytesPerSecond / 1_073_741_824)
        }
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MiB/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.1f KiB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    private func linePath(values: [Double?], in size: CGSize, maxValue: Double) -> Path {
        guard !values.isEmpty, maxValue > 0, size.width > 0, size.height > 0 else { return Path() }

        // Render immediately with a single sample so the chart never appears "empty"
        // while waiting for the second polling cycle.
        if values.count == 1, let first = values[0] {
            let normalized = min(max(first / maxValue, 0), 1)
            let y = size.height - (CGFloat(normalized) * size.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            return path
        }

        let stepX = size.width / CGFloat(max(values.count - 1, 1))
        var path = Path()
        var segmentOpen = false

        for (idx, value) in values.enumerated() {
            guard let value else {
                segmentOpen = false
                continue
            }

            let normalized = min(max(value / maxValue, 0), 1)
            let x = CGFloat(idx) * stepX
            let y = size.height - (CGFloat(normalized) * size.height)
            let point = CGPoint(x: x, y: y)

            if segmentOpen {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                segmentOpen = true
            }
        }

        return path
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
