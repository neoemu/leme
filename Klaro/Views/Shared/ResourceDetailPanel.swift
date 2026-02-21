import SwiftUI

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

struct ResourceDetailPanel: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ResourceDetailViewModel
    @State private var selectedTab: ResourceDetailTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .background(Theme.Colors.detailPanelBackground)
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
            }
            .buttonStyle(.plain)
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
            selectedTab = tab
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(Theme.Fonts.sidebarItem)
            }
            .padding(.horizontal, Theme.Dimensions.spacing)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(selectedTab == tab ? Theme.Colors.accent.opacity(0.15) : .clear)
            )
            .foregroundStyle(selectedTab == tab ? Theme.Colors.accent : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.Dimensions.spacing)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.isLoading {
            VStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading details...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            switch selectedTab {
            case .overview:
                overviewTab
            case .yaml:
                yamlTab
            case .events:
                eventsTab
            }
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Dimensions.spacing * 2) {
                metadataSection
                if !viewModel.labels.isEmpty {
                    labelsSection
                }
                if !viewModel.annotations.isEmpty {
                    annotationsSection
                }
            }
            .padding(Theme.Dimensions.padding)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            sectionHeader("Metadata")

            ForEach(Array(viewModel.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                detailRow(key: key, value: value)
            }
        }
    }

    private var labelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            sectionHeader("Labels")

            ForEach(Array(viewModel.labels.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                detailRow(key: key, value: value)
            }
        }
    }

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            sectionHeader("Annotations")

            ForEach(Array(viewModel.annotations.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                detailRow(key: key, value: value)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.subtitle)
            .foregroundStyle(.primary)
    }

    private func detailRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(value.isEmpty ? "-" : value)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textSelection(.enabled)
        }
    }

    // MARK: - YAML Tab

    private var yamlTab: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(viewModel.resourceYAML.isEmpty ? "No YAML available" : viewModel.resourceYAML)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textSelection(.enabled)
                .padding(Theme.Dimensions.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    LazyVStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
                        ForEach(viewModel.events) { event in
                            eventRow(event)
                            Divider()
                        }
                    }
                    .padding(Theme.Dimensions.padding)
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
