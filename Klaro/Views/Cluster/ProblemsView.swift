import SwiftUI

/// "What is broken right now": aggregates unhealthy pods, degraded workloads,
/// node conditions, pending PVCs and failed jobs, with correlated Warning
/// events and direct navigation to the affected resource.
struct ProblemsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    @State private var viewModel = ProblemsViewModel()
    @State private var expandedIDs: Set<String> = []

    private var refreshKey: String {
        "\(appState.activeClusterID?.uuidString ?? "")|\(appState.selectedNamespace ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: refreshKey) {
            await load(showSpinner: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await load(showSpinner: false)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "stethoscope")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Problems")
                .font(Theme.Fonts.title)

            if viewModel.criticalCount > 0 {
                countPill("\(viewModel.criticalCount) critical", color: Theme.Colors.failed)
            }
            if viewModel.warningCount > 0 {
                countPill("\(viewModel.warningCount) warning\(viewModel.warningCount == 1 ? "" : "s")", color: Theme.Colors.warning)
            }
            if !viewModel.isLoading, viewModel.problems.isEmpty, viewModel.errorMessage == nil, viewModel.lastUpdated != nil {
                countPill("all clear", color: Theme.Colors.running)
            }

            Spacer()

            if let namespace = appState.selectedNamespace {
                Text(namespace)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("updated \(lastUpdated.relativeAge) ago")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await load(showSpinner: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help("Scan the cluster again")
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.padding)
    }

    private func countPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.problems.isEmpty && viewModel.lastUpdated == nil {
            VStack(spacing: Theme.Dimensions.spacing) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning cluster…")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.problems.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Scan Failed",
                message: error
            )
        } else if viewModel.problems.isEmpty {
            EmptyStateView(
                icon: "checkmark.circle",
                title: "No Problems Found",
                message: appState.selectedNamespace.map { "Everything in namespace \($0) looks healthy." }
                    ?? "Everything in this cluster looks healthy."
            )
        } else {
            problemsList
        }
    }

    private var problemsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let critical = viewModel.problems.filter { $0.severity == .critical }
                let warnings = viewModel.problems.filter { $0.severity == .warning }

                if !critical.isEmpty {
                    severityHeader("Critical", count: critical.count, color: Theme.Colors.failed)
                    ForEach(critical) { problemRow($0) }
                }

                if !warnings.isEmpty {
                    severityHeader("Warnings", count: warnings.count, color: Theme.Colors.warning)
                    ForEach(warnings) { problemRow($0) }
                }
            }
            .padding(.vertical, Theme.Dimensions.smallSpacing)
        }
    }

    private func severityHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.top, Theme.Dimensions.spacing)
        .padding(.bottom, Theme.Dimensions.smallSpacing)
    }

    // MARK: - Rows

    private func problemRow(_ item: ProblemItem) -> some View {
        let events = viewModel.events(for: item)
        let isExpanded = expandedIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: item.kind.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: 16)
                    .help(item.kind.rawValue)

                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let namespace = item.namespace {
                    Text(namespace)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.severity == .critical ? Theme.Colors.failed : Theme.Colors.warning)

                Spacer()

                if let age = item.age {
                    AgeLabel(date: age)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            Text(item.detail)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(isExpanded ? nil : 1)
                .padding(.leading, 16 + CGFloat(Theme.Dimensions.spacing))

            if isExpanded {
                if events.isEmpty {
                    Text("No recent Warning events for this resource.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .padding(.leading, 16 + CGFloat(Theme.Dimensions.spacing))
                        .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events) { event in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Dimensions.smallSpacing) {
                                Text(event.reason)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.warning)
                                Text(event.message)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .textSelection(.enabled)
                                Spacer()
                                if event.count > 1 {
                                    Text("×\(event.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.tertiaryText)
                                }
                                if let lastSeen = event.lastSeen {
                                    AgeLabel(date: lastSeen)
                                }
                            }
                        }
                    }
                    .padding(Theme.Dimensions.smallSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .padding(.leading, 16 + CGFloat(Theme.Dimensions.spacing))
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.12)) {
                if isExpanded {
                    expandedIDs.remove(item.id)
                } else {
                    expandedIDs.insert(item.id)
                }
            }
        }
        .contextMenu {
            Button {
                goToResource(item)
            } label: {
                Label("Go to Resource", systemImage: "arrow.right.circle")
            }

            if item.kind == .pod {
                Button {
                    appState.requestPodLogs(podName: item.name, namespace: item.namespace ?? "default")
                } label: {
                    Label("View Logs", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }

    // MARK: - Actions

    private func goToResource(_ item: ProblemItem) {
        if item.kind.isNamespaced {
            appState.selectedNamespace = item.namespace
        }
        appState.sidebarSelection = .resource(item.kind)
        let resourceID = item.namespace.map { "\($0)/\(item.name)" } ?? item.name
        appState.showResourceDetail(resourceID)
    }

    @MainActor
    private func load(showSpinner: Bool) async {
        guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else { return }
        await viewModel.load(
            client: client,
            namespace: appState.selectedNamespace,
            contextName: appState.activeCluster?.contextName,
            showSpinner: showSpinner
        )
    }
}
