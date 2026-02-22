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

    private var overviewTab: some View {
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

                if !viewModel.annotations.isEmpty {
                    cardSection(title: "Annotations") {
                        ForEach(Array(viewModel.annotations.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            detailRow(key: key, value: value)
                        }
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

    // MARK: - YAML Tab

    @ViewBuilder
    private var yamlTab: some View {
        if viewModel.resourceYAML.isEmpty {
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
                source: .constant(viewModel.resourceYAML),
                language: .yaml,
                theme: .ocean,
                flags: [.selectable],
                indentStyle: .softTab(width: 2)
            )
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
