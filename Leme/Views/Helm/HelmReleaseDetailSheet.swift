import SwiftUI

/// Release drill-down: revision history with rollback, values and manifest.
struct HelmReleaseDetailSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case values = "Values"
        case manifest = "Manifest"

        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    let release: HelmRelease
    let initialTab: Tab
    let service: HelmService
    /// Called after a rollback succeeds so the list refreshes.
    let onReleaseChanged: () -> Void

    @State private var tab: Tab
    @State private var revisions: [HelmReleaseRevision] = []
    @State private var isLoadingHistory = false
    @State private var valuesText = ""
    @State private var valuesLines: [String] = []
    @State private var showAllValues = false
    /// nil shows the latest revision's values.
    @State private var valuesRevision: Int?
    @State private var isLoadingValues = false
    @State private var manifestText = ""
    @State private var manifestLines: [String] = []
    @State private var isLoadingManifest = false
    @State private var errorMessage: String?
    @State private var isRollingBack = false
    @State private var statusMessage: String?
    @State private var rollbackTarget: HelmReleaseRevision?
    @State private var dangerAction: PendingDangerAction?
    @State private var copiedContent = false

    init(release: HelmRelease, initialTab: Tab = .history, service: HelmService, onReleaseChanged: @escaping () -> Void) {
        self.release = release
        self.initialTab = initialTab
        self.service = service
        self.onReleaseChanged = onReleaseChanged
        _tab = State(initialValue: initialTab)
    }

    private var latestRevision: Int {
        revisions.map(\.revision).max() ?? release.revision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.spacing)

            banners

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(width: 680, height: 520)
        .task(id: tab) { await loadCurrentTab() }
        .onChange(of: showAllValues) { _, _ in
            Task { await loadValues() }
        }
        .onChange(of: valuesRevision) { _, _ in
            Task { await loadValues() }
        }
        .confirmationDialog(
            "Rollback \(release.name) to revision \(rollbackTarget?.revision ?? 0)?",
            isPresented: Binding(
                get: { rollbackTarget != nil },
                set: { if !$0 { rollbackTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Rollback", role: .destructive) {
                if let target = rollbackTarget {
                    Task { await performRollback(to: target) }
                }
                rollbackTarget = nil
            }
            Button("Cancel", role: .cancel) {
                rollbackTarget = nil
            }
        } message: {
            Text("Helm creates a new revision restoring the chart and values of revision \(rollbackTarget?.revision ?? 0).")
        }
        .sheet(item: $dangerAction) { action in
            DangerConfirmationSheet(
                action: action,
                clusterName: appState.activeCluster?.displayName ?? ""
            ) {
                dangerAction = nil
            }
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(release.name)
                    .font(Theme.Fonts.title)
                Text("\(release.namespace) • \(release.chart)")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            StatusBadge(status: release.displayStatus)
        }
        .padding(Theme.Dimensions.padding)
    }

    @ViewBuilder
    private var banners: some View {
        if let errorMessage {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.failed)
                Text(errorMessage)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.failed)
                    .lineLimit(2)
                Spacer()
                Button {
                    self.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.smallSpacing)
            .background(Theme.Colors.errorBackground)
        } else if let statusMessage {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.running)
                Text(statusMessage)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.smallSpacing)
            .background(Theme.Colors.successBackground)
        }
    }

    private var footer: some View {
        HStack {
            if isRollingBack {
                ProgressView()
                    .controlSize(.small)
                Text("Rolling back…")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Dimensions.padding)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .history:
            historyContent
        case .values:
            textContent(valuesText, lines: valuesLines, isLoading: isLoadingValues, emptyMessage: "No user-supplied values for this release.") {
                HStack(spacing: Theme.Dimensions.spacing) {
                    Picker("Revision:", selection: $valuesRevision) {
                        Text("Current (#\(latestRevision))").tag(Int?.none)
                        ForEach(revisions.sorted { $0.revision > $1.revision }.filter { $0.revision != latestRevision }) { revision in
                            Text("#\(revision.revision) — \(revision.chart)").tag(Int?.some(revision.revision))
                        }
                    }
                    .controlSize(.small)
                    .fixedSize()

                    Toggle("Show computed values (--all)", isOn: $showAllValues)
                        .toggleStyle(.checkbox)
                        .font(Theme.Fonts.caption)
                }
            }
        case .manifest:
            textContent(manifestText, lines: manifestLines, isLoading: isLoadingManifest, emptyMessage: "No manifest available.") {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if isLoadingHistory && revisions.isEmpty {
            loadingIndicator("Loading history…")
        } else if revisions.isEmpty {
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No History",
                message: "No revisions found for this release."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(revisions.sorted { $0.revision > $1.revision }) { revision in
                        revisionRow(revision)
                        Divider()
                            .padding(.leading, Theme.Dimensions.padding)
                    }
                }
            }
        }
    }

    private func revisionRow(_ revision: HelmReleaseRevision) -> some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Text("#\(revision.revision)")
                .font(Theme.Fonts.monoMedium)
                .foregroundStyle(.primary)
                .frame(width: 44, alignment: .leading)

            StatusBadge(status: revision.displayStatus)
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(revision.chart)\(revision.appVersion.isEmpty ? "" : " • app \(revision.appVersion)")")
                    .font(Theme.Fonts.tableCell)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(revision.description)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if let updated = revision.updated {
                AgeLabel(date: updated)
            }

            if revision.revision == latestRevision {
                Text("CURRENT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Colors.running)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Theme.Colors.running.opacity(0.15))
                    )
            } else {
                Button("Values") {
                    valuesRevision = revision.revision
                    tab = .values
                }
                .controlSize(.small)
                .help("Show the values of revision \(revision.revision)")

                Button("Rollback") {
                    requestRollback(to: revision)
                }
                .controlSize(.small)
                .disabled(isRollingBack)
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, Theme.Dimensions.smallSpacing)
    }

    @ViewBuilder
    private func textContent<Accessory: View>(
        _ text: String,
        lines: [String],
        isLoading: Bool,
        emptyMessage: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                accessory()
                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedContent = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copiedContent = false
                    }
                } label: {
                    Image(systemName: copiedContent ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedContent ? Theme.Colors.running : Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
                .disabled(text.isEmpty)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.bottom, Theme.Dimensions.smallSpacing)

            Divider()

            if isLoading && text.isEmpty {
                loadingIndicator("Loading…")
            } else if text.isEmpty {
                EmptyStateView(icon: "doc.text", title: "Nothing Here", message: emptyMessage)
            } else {
                // Rendered line by line in a LazyVStack: a single Text would
                // freeze the main thread laying out multi-megabyte manifests.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(lines[index].isEmpty ? " " : lines[index])
                                .font(Theme.Fonts.monoSmall)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Theme.Dimensions.padding)
                }
                // Dim stale content while a reload (revision/--all change) is in flight.
                .opacity(isLoading ? 0.45 : 1)
                .animation(Theme.Animations.contentTransition, value: isLoading)
            }
        }
    }

    private func loadingIndicator(_ message: String) -> some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    @MainActor
    private func loadCurrentTab() async {
        switch tab {
        case .history:
            await loadHistory()
        case .values:
            await loadValues()
            // The revision picker needs the history even when this tab opens first.
            if revisions.isEmpty {
                await loadHistory()
            }
        case .manifest:
            await loadManifest()
        }
    }

    @MainActor
    private func loadHistory() async {
        isLoadingHistory = true
        do {
            revisions = try await service.history(releaseName: release.name, namespace: release.namespace)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
        }
        isLoadingHistory = false
    }

    @MainActor
    private func loadValues() async {
        isLoadingValues = true
        do {
            valuesText = try await service.values(
                releaseName: release.name,
                namespace: release.namespace,
                allValues: showAllValues,
                revision: valuesRevision
            )
            // helm prints "null" for releases installed without custom values.
            if valuesText == "null" {
                valuesText = ""
            }
            valuesLines = valuesText.isEmpty ? [] : valuesText.components(separatedBy: "\n")
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load values: \(error.localizedDescription)"
        }
        isLoadingValues = false
    }

    @MainActor
    private func loadManifest() async {
        guard manifestText.isEmpty else { return }
        isLoadingManifest = true
        do {
            manifestText = try await service.manifest(releaseName: release.name, namespace: release.namespace)
            manifestLines = manifestText.isEmpty ? [] : manifestText.components(separatedBy: "\n")
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load manifest: \(error.localizedDescription)"
        }
        isLoadingManifest = false
    }

    // MARK: - Rollback

    private func requestRollback(to revision: HelmReleaseRevision) {
        if settingsStore.isProduction(appState.activeCluster) {
            dangerAction = PendingDangerAction(
                title: "Rollback \(release.name) to revision \(revision.revision)",
                message: "This rolls back helm release \(release.name) in namespace \(release.namespace) on a production cluster.",
                confirmText: release.name,
                confirmLabel: "Rollback"
            ) {
                Task { await performRollback(to: revision) }
            }
        } else {
            rollbackTarget = revision
        }
    }

    @MainActor
    private func performRollback(to revision: HelmReleaseRevision) async {
        isRollingBack = true
        statusMessage = nil
        do {
            try await service.rollback(
                releaseName: release.name,
                toRevision: revision.revision,
                namespace: release.namespace
            )
            statusMessage = "Rolled back to revision \(revision.revision)."
            errorMessage = nil
            await loadHistory()
            onReleaseChanged()
        } catch {
            errorMessage = "Rollback failed: \(error.localizedDescription)"
        }
        isRollingBack = false
    }
}
