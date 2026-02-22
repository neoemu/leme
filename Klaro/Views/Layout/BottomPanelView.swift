import AppKit
import SwiftUI

struct BottomPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var podLogsViewModel: PodLogsViewModel?
    @State private var terminalViewModel = TerminalViewModel()

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Tab bar
            tabBar

            // Content area
            panelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: appState.bottomPanelHeight)
        .background(Theme.Colors.bottomPanelBackground)
        .onChange(of: appState.bottomPanelMode) { oldValue, newValue in
            if oldValue == .logs && newValue != .logs {
                podLogsViewModel?.stopStreaming()
            }
            if newValue == .logs {
                startLogsIfNeeded()
            }
        }
        .onChange(of: appState.logTargetPodName) { _, _ in
            if appState.bottomPanelMode == .logs {
                startLogsIfNeeded()
            }
        }
        .onAppear {
            if appState.bottomPanelMode == .logs {
                startLogsIfNeeded()
            }
        }
        .onDisappear {
            podLogsViewModel?.stopStreaming()
            terminalViewModel.closeAllSessions()
        }
    }

    private var dragHandle: some View {
        @Bindable var appState = appState

        return Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newHeight = appState.bottomPanelHeight - value.translation.height
                        appState.bottomPanelHeight = min(
                            max(newHeight, Theme.Dimensions.bottomPanelMinHeight),
                            Theme.Dimensions.bottomPanelMaxHeight
                        )
                    }
            )
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([BottomPanelMode.logs, .terminal], id: \.self) { mode in
                tabButton(for: mode)
            }

            // Terminal session tabs and controls (shown when terminal mode is active)
            if appState.bottomPanelMode == .terminal {
                terminalSessionTabs
            }

            Spacer()

            // Pod name label for logs tab
            if appState.bottomPanelMode == .logs, let vm = podLogsViewModel {
                Text("\(vm.namespace)/\(vm.podName)")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .padding(.trailing, Theme.Dimensions.spacing)
            }

            // Close button
            Button {
                appState.isBottomPanelOpen = false
                podLogsViewModel?.stopStreaming()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, Theme.Dimensions.padding)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Terminal Session Tabs

    private var terminalSessionTabs: some View {
        HStack(spacing: 0) {
            // Separator between mode tabs and session tabs
            Divider()
                .frame(height: 16)
                .padding(.horizontal, Theme.Dimensions.spacing)

            // Session tabs
            ForEach(terminalViewModel.sessions) { session in
                terminalSessionTab(for: session)
            }

            // Add new terminal session button
            Menu {
                Button {
                    let contextName = appState.activeCluster?.contextName
                    terminalViewModel.createLocalSession(kubeContext: contextName)
                } label: {
                    Label("Local Shell", systemImage: "terminal")
                }

                if let podName = appState.execTargetPodName,
                   let namespace = appState.execTargetNamespace,
                   let container = appState.execTargetContainer {
                    Button {
                        let contextName = appState.activeCluster?.contextName
                        terminalViewModel.createPodExecSession(
                            podName: podName,
                            namespace: namespace,
                            container: container,
                            kubeContext: contextName
                        )
                    } label: {
                        Label("Exec into \(podName)", systemImage: "server.rack")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .padding(.leading, Theme.Dimensions.smallSpacing)
        }
    }

    private func terminalSessionTab(for session: TerminalSession) -> some View {
        let isActive = terminalViewModel.activeSessionID == session.id

        return HStack(spacing: Theme.Dimensions.smallSpacing) {
            Image(systemName: isLocalSession(session) ? "terminal" : "server.rack")
                .font(.system(size: 9))
            Text(session.title)
                .font(Theme.Fonts.caption)
                .lineLimit(1)

            // Close session button
            Button {
                terminalViewModel.closeSession(id: session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                .fill(isActive ? Theme.Colors.accent.opacity(0.1) : .clear)
        )
        .foregroundStyle(isActive ? Theme.Colors.accent : .secondary)
        .onTapGesture {
            terminalViewModel.activeSessionID = session.id
        }
    }

    private func isLocalSession(_ session: TerminalSession) -> Bool {
        if case .local = session.type { return true }
        return false
    }

    private func tabButton(for mode: BottomPanelMode) -> some View {
        Button {
            appState.bottomPanelMode = mode
        } label: {
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                Text(mode.rawValue)
                    .font(Theme.Fonts.sidebarItem)
            }
            .padding(.horizontal, Theme.Dimensions.spacing)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(appState.bottomPanelMode == mode ? Theme.Colors.accent.opacity(0.15) : .clear)
            )
            .foregroundStyle(appState.bottomPanelMode == mode ? Theme.Colors.accent : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, Theme.Dimensions.spacing)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch appState.bottomPanelMode {
        case .logs:
            if let vm = podLogsViewModel {
                LogViewerView(viewModel: vm)
            } else {
                placeholderContent(
                    icon: "doc.text.magnifyingglass",
                    text: "Select a pod and choose View Logs to stream logs"
                )
            }
        case .terminal:
            terminalContent
        case .yaml:
            placeholderContent(
                icon: "doc.plaintext",
                text: "YAML editor moved to the side panel"
            )
        }
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContent: some View {
        if let session = terminalViewModel.activeSession {
            let contextName = appState.activeCluster?.contextName
            TerminalContainerView(
                session: session,
                kubeContext: contextName
            )
            .id(session.id)
        } else {
            // No sessions yet - show prompt to create one
            VStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: "terminal")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.tertiaryText)
                Text("No terminal sessions")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                Button {
                    let contextName = appState.activeCluster?.contextName
                    terminalViewModel.createLocalSession(kubeContext: contextName)
                } label: {
                    HStack(spacing: Theme.Dimensions.smallSpacing) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("New Local Shell")
                            .font(Theme.Fonts.sidebarItem)
                    }
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.vertical, Theme.Dimensions.spacing)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                            .fill(Theme.Colors.accent.opacity(0.15))
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholderContent(icon: String, text: String) -> some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(text)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Log Streaming

    private func startLogsIfNeeded() {
        guard let podName = appState.logTargetPodName,
              let namespace = appState.logTargetNamespace else {
            return
        }

        // If already streaming the same pod, do nothing
        if let existing = podLogsViewModel,
           existing.podName == podName,
           existing.namespace == namespace,
           existing.isStreaming {
            return
        }

        // Stop any existing stream
        podLogsViewModel?.stopStreaming()

        let vm = PodLogsViewModel(podName: podName, namespace: namespace)
        if let container = appState.logTargetContainer {
            vm.selectedContainer = container
        }
        podLogsViewModel = vm

        Task {
            do {
                guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                    vm.errorMessage = "No active cluster connection"
                    return
                }
                vm.startStreaming(client: client)
            } catch {
                vm.errorMessage = error.localizedDescription
            }
        }
    }
}
