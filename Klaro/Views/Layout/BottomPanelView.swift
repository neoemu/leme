import AppKit
import SwiftUI

struct BottomPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @State private var logSessions: [PodLogsViewModel] = []
    @State private var activeLogSessionID: UUID?
    @State private var terminalViewModel = TerminalViewModel()
    @State private var handledPodExecRequestID: UUID?
    @State private var isHoveringDragHandle = false
    @State private var isDraggingDragHandle = false

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
                stopAllLogStreaming()
            }
            if newValue == .logs {
                if appState.pendingPodLogsRequestID != nil {
                    startLogsIfNeeded()
                } else {
                    resumeActiveLogStreamingIfNeeded()
                }
            } else if newValue == .terminal {
                startPodExecIfNeeded()
            }
        }
        .onChange(of: appState.pendingPodLogsRequestID) { _, _ in
            startLogsIfNeeded()
        }
        .onChange(of: appState.pendingPodExecRequestID) { _, _ in
            startPodExecIfNeeded()
        }
        .onAppear {
            if appState.bottomPanelMode == .logs {
                if appState.pendingPodLogsRequestID != nil {
                    startLogsIfNeeded()
                } else {
                    resumeActiveLogStreamingIfNeeded()
                }
            } else if appState.bottomPanelMode == .terminal {
                startPodExecIfNeeded()
            }
        }
        .onDisappear {
            stopAllLogStreaming()
            terminalViewModel.closeAllSessions()
        }
    }

    private var dragHandle: some View {
        @Bindable var appState = appState

        let isHighlighted = isHoveringDragHandle || isDraggingDragHandle

        return ZStack {
            Rectangle()
                .fill(Theme.Colors.separator.opacity(isHighlighted ? 0.75 : 0.35))
                .frame(height: 1)
                .offset(y: -4)

            Capsule()
                .fill(isHighlighted ? Theme.Colors.accent.opacity(0.75) : Theme.Colors.separator.opacity(0.6))
                .frame(width: 42, height: 3)
                .shadow(color: isHighlighted ? Theme.Colors.accent.opacity(0.25) : .clear, radius: 2, y: 0)
        }
        .frame(height: 10)
        .background(
            Rectangle()
                .fill(isHighlighted ? Theme.Colors.accent.opacity(0.08) : .clear)
        )
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringDragHandle = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDraggingDragHandle = true
                        let newHeight = appState.bottomPanelHeight - value.translation.height
                        appState.bottomPanelHeight = min(
                            max(newHeight, Theme.Dimensions.bottomPanelMinHeight),
                            Theme.Dimensions.bottomPanelMaxHeight
                        )
                    }
                    .onEnded { _ in
                        isDraggingDragHandle = false
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
            } else if appState.bottomPanelMode == .logs {
                logSessionTabs
            }

            Spacer()

            // Pod name label for logs tab
            if appState.bottomPanelMode == .logs, let vm = activeLogSession {
                Text("\(vm.namespace)/\(vm.podName)")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .padding(.trailing, Theme.Dimensions.spacing)
            }

            // Close button
            Button {
                appState.isBottomPanelOpen = false
                stopAllLogStreaming()
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

    // MARK: - Log Session Tabs

    private var logSessionTabs: some View {
        HStack(spacing: 0) {
            Divider()
                .frame(height: 16)
                .padding(.horizontal, Theme.Dimensions.spacing)

            ForEach(logSessions, id: \.id) { session in
                logSessionTab(for: session)
            }
        }
    }

    private func logSessionTab(for session: PodLogsViewModel) -> some View {
        let isActive = activeLogSessionID == session.id

        return HStack(spacing: Theme.Dimensions.smallSpacing) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 9))
            Text(session.tabTitle)
                .font(Theme.Fonts.caption)
                .lineLimit(1)

            Button {
                closeLogSession(id: session.id)
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
            activeLogSessionID = session.id
            startStreamingIfNeeded(for: session)
        }
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
                   let namespace = appState.execTargetNamespace {
                    Button {
                        let contextName = appState.activeCluster?.contextName
                        terminalViewModel.createPodExecSession(
                            podName: podName,
                            namespace: namespace,
                            container: appState.execTargetContainer,
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
            if let vm = activeLogSession {
                LogViewerView(viewModel: vm)
                    .id(vm.id)
            } else {
                placeholderContent(
                    icon: "doc.text.magnifyingglass",
                    text: "Select a pod and choose View Logs to open a log tab"
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

    private var activeLogSession: PodLogsViewModel? {
        guard let id = activeLogSessionID else { return logSessions.first }
        return logSessions.first { $0.id == id }
    }

    private func startLogsIfNeeded() {
        guard let podName = appState.logTargetPodName,
              let namespace = appState.logTargetNamespace,
              appState.bottomPanelMode == .logs else {
            return
        }
        let container = appState.logTargetContainer
        let aggregatePods = appState.logTargetPodNames

        if let existing = logSessions.first(where: { session in
            session.podName == podName &&
            session.namespace == namespace &&
            session.selectedContainer == container &&
            session.aggregatePodNames == aggregatePods
        }) {
            activeLogSessionID = existing.id
            startStreamingIfNeeded(for: existing)
            appState.pendingPodLogsRequestID = nil
            return
        }

        let vm = PodLogsViewModel(podName: podName, namespace: namespace)
        if let container {
            vm.selectedContainer = container
        }
        vm.aggregatePodNames = aggregatePods
        logSessions.append(vm)
        activeLogSessionID = vm.id
        startStreamingIfNeeded(for: vm)
        appState.pendingPodLogsRequestID = nil
    }

    private func startStreamingIfNeeded(for vm: PodLogsViewModel) {
        guard !vm.isStreaming else { return }
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

    private func stopAllLogStreaming() {
        for session in logSessions {
            session.stopStreaming()
        }
    }

    private func resumeActiveLogStreamingIfNeeded() {
        if let active = activeLogSession {
            startStreamingIfNeeded(for: active)
            return
        }

        if let first = logSessions.first {
            activeLogSessionID = first.id
            startStreamingIfNeeded(for: first)
        }
    }

    private func closeLogSession(id: UUID) {
        guard let index = logSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = logSessions.remove(at: index)
        session.stopStreaming()

        if activeLogSessionID == id {
            activeLogSessionID = logSessions.last?.id
            if appState.bottomPanelMode == .logs, let active = activeLogSession {
                startStreamingIfNeeded(for: active)
            }
        }
    }

    private func startPodExecIfNeeded() {
        guard appState.bottomPanelMode == .terminal,
              let requestID = appState.pendingPodExecRequestID,
              requestID != handledPodExecRequestID,
              let podName = appState.execTargetPodName,
              let namespace = appState.execTargetNamespace else {
            return
        }

        let container = appState.execTargetContainer

        if let existing = terminalViewModel.sessions.first(where: { session in
            if case .podExec(let existingPod, let existingNamespace, let existingContainer) = session.type {
                return existingPod == podName &&
                    existingNamespace == namespace &&
                    existingContainer == container
            }
            return false
        }) {
            terminalViewModel.activeSessionID = existing.id
        } else {
            let contextName = appState.activeCluster?.contextName
            terminalViewModel.createPodExecSession(
                podName: podName,
                namespace: namespace,
                container: container,
                kubeContext: contextName
            )
        }

        handledPodExecRequestID = requestID
        appState.pendingPodExecRequestID = nil
    }
}
