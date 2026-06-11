import AppKit
import SwiftUI

struct MainLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    @Environment(PortForwardManager.self) private var portForwardManager
    @Environment(SettingsStore.self) private var settingsStore
    @State private var isPortForwardPopoverPresented = false

    @AppStorage("sidebarPanelWidth") private var sidebarWidth: Double = 280
    @AppStorage("sidebarPanelVisible") private var isSidebarVisible: Bool = true
    /// Live width during drags; persisted to `sidebarWidth` only on drag end
    /// (writing UserDefaults every tick makes the drag stutter).
    @State private var sidebarLiveWidth: CGFloat = 280
    @State private var sidebarDragStartWidth: Double?
    @State private var isHoveringSidebarHandle = false

    private static let sidebarMinWidth: Double = 230
    private static let sidebarMaxWidth: Double = 400

    private var isProductionCluster: Bool {
        settingsStore.isProduction(appState.activeCluster)
    }

    private var productionBanner: some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
            Text("PRODUCTION — \(appState.activeCluster?.displayName ?? "")")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, 3)
        .background(Theme.Colors.failed.opacity(0.85))
    }

    var body: some View {
        @Bindable var appState = appState

        return HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView()
                    .frame(width: sidebarLiveWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Colors.sidebarBackground.ignoresSafeArea())

                sidebarResizeHandle
            }

            detailColumn
        }
        .onAppear {
            sidebarLiveWidth = CGFloat(min(max(sidebarWidth, Self.sidebarMinWidth), Self.sidebarMaxWidth))
        }
        .overlay {
            if appState.isCommandPaletteOpen {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .overlay {
            if appState.isGlobalSearchOpen {
                GlobalSearchView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isCommandPaletteOpen)
        .animation(.easeInOut(duration: 0.15), value: appState.isGlobalSearchOpen)
        .animation(.easeInOut(duration: 0.15), value: isSidebarVisible)
        .sheet(item: $appState.pendingDangerAction) { action in
            DangerConfirmationSheet(
                action: action,
                clusterName: appState.activeCluster?.displayName ?? ""
            ) {
                appState.pendingDangerAction = nil
            }
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = appState.toastMessage {
            Text(message)
                .font(Theme.Fonts.caption)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThickMaterial))
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var detailColumn: some View {
        @Bindable var appState = appState

        return VStack(spacing: 0) {
                detailTopBar

                if isProductionCluster {
                    productionBanner
                }

                ContentAreaView()

                if appState.isBottomPanelOpen {
                    BottomPanelView()
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.contentBackground)
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeInOut(duration: 0.2), value: appState.isBottomPanelOpen)
            .overlay {
                if appState.isYAMLEditorOpen {
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.closeYAMLEditor()
                            }

                        ResizableYAMLEditorView(
                            initialWidth: appState.yamlEditorWidth,
                            onResizeEnded: { finalWidth in
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    appState.setYAMLEditorWidth(finalWidth, persist: true)
                                }
                            }
                        )
                        .zIndex(1)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: -2, y: 0)
                        .transition(.move(edge: .trailing))
                    }
                } else if appState.isDetailPanelOpen {
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.isDetailPanelOpen = false
                                appState.selectedResourceID = nil
                            }

                        ResizableInspectorDetailView(
                            initialWidth: appState.inspectorDetailWidth,
                            onResizeEnded: { finalWidth in
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    appState.setInspectorDetailWidth(finalWidth, persist: true)
                                }
                            }
                        )
                        .zIndex(1)
                        .shadow(color: .black.opacity(0.25), radius: 6, x: -2, y: 0)
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: appState.isDetailPanelOpen)
            .animation(.easeInOut(duration: 0.15), value: appState.isYAMLEditorOpen)
    }

    /// Thin action strip occupying the (hidden) title bar band, Codex-style.
    private var detailTopBar: some View {
        HStack(spacing: 16) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .help("Toggle sidebar")
            // Keep clear of the traffic lights when the sidebar is collapsed.
            .padding(.leading, isSidebarVisible ? 0 : 74)

            Spacer()

            Button {
                Task {
                    await clusterViewModel.reloadContexts(appState: appState)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .help("Reload kubeconfig")

            Button {
                isPortForwardPopoverPresented.toggle()
            } label: {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .overlay(alignment: .topTrailing) {
                if portForwardManager.activeCount > 0 {
                    Text("\(portForwardManager.activeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.Colors.accent))
                        .offset(x: 8, y: -6)
                }
            }
            .help("Active port forwards")
            .popover(isPresented: $isPortForwardPopoverPresented, arrowEdge: .bottom) {
                PortForwardListPopover()
            }

            Button {
                if appState.isYAMLEditorOpen {
                    appState.closeYAMLEditor()
                } else {
                    appState.isDetailPanelOpen.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .help("Toggle inspector panel")

            SettingsLink {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .help("Settings")
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .frame(height: 38)
    }

    /// Hairline divider between sidebar and content. It only occupies 1pt of
    /// layout; the draggable hit area is a wider invisible overlay so no dark
    /// gap shows between the panels.
    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        guard hovering != isHoveringSidebarHandle else { return }
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        isHoveringSidebarHandle = hovering
                    }
                    .gesture(
                        // Global coordinates: the handle moves while dragging,
                        // so local translations feed back into the gesture and
                        // make the resize flicker.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if sidebarDragStartWidth == nil {
                                    sidebarDragStartWidth = Double(sidebarLiveWidth)
                                }
                                guard let startWidth = sidebarDragStartWidth else { return }
                                let proposed = startWidth + value.translation.width
                                let clamped = min(max(proposed, Self.sidebarMinWidth), Self.sidebarMaxWidth)
                                let snapped = (clamped / 2).rounded() * 2

                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    sidebarLiveWidth = CGFloat(snapped)
                                }
                            }
                            .onEnded { _ in
                                sidebarDragStartWidth = nil
                                sidebarWidth = Double(sidebarLiveWidth)
                            }
                    )
            }
            .accessibilityLabel("Resize sidebar")
    }
}

private struct ResizableYAMLEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel
    let initialWidth: CGFloat
    let onResizeEnded: (CGFloat) -> Void

    @State private var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var isHoveringResizeHandle = false

    init(initialWidth: CGFloat, onResizeEnded: @escaping (CGFloat) -> Void) {
        self.initialWidth = initialWidth
        self.onResizeEnded = onResizeEnded
        let clampedWidth = min(max(initialWidth, AppState.yamlEditorMinWidth), AppState.yamlEditorMaxWidth)
        _width = State(initialValue: clampedWidth)
    }

    var body: some View {
        @Bindable var appState = appState

        return HStack(spacing: 0) {
            resizeHandle
            YAMLEditorView(
                source: $appState.yamlSource,
                title: appState.yamlEditorTitle,
                originalSource: appState.yamlOriginalSource,
                onClose: {
                    appState.closeYAMLEditor()
                },
                onApply: { yaml in
                    guard let client = try await clusterViewModel.clientForActiveCluster(appState: appState) else {
                        throw KubernetesServiceError.operationFailed("No active cluster connection.")
                    }

                    let service = KubernetesService(client: client)
                    let result = try await service.applyYAML(
                        yaml,
                        originalYAML: appState.yamlOriginalSource,
                        in: appState.selectedNamespace,
                        context: appState.activeCluster?.contextName
                    )
                    appState.yamlOriginalSource = yaml
                    if result.warnings.isEmpty {
                        return "Applied via \(result.mode.rawValue)"
                    }
                    return "Applied via \(result.mode.rawValue) with \(result.warnings.count) warning(s)"
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Colors.contentBackground)
        }
        .frame(width: width)
        .onAppear {
            width = clamp(initialWidth)
        }
        .onDisappear {
            if isHoveringResizeHandle {
                NSCursor.pop()
                isHoveringResizeHandle = false
            }
        }
    }

    private var resizeHandle: some View {
        ZStack(alignment: .trailing) {
            Color.clear
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHoveringResizeHandle else { return }

            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            isHoveringResizeHandle = hovering
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }

                    guard let startWidth = dragStartWidth else { return }
                    let proposedWidth = clamp(startWidth - value.translation.width)
                    let snappedWidth = (proposedWidth / 2).rounded() * 2

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = snappedWidth
                    }
                }
                .onEnded { value in
                    defer {
                        dragStartWidth = nil
                    }

                    guard let startWidth = dragStartWidth else {
                        onResizeEnded(width)
                        return
                    }

                    let proposedWidth = clamp(startWidth - value.translation.width)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = proposedWidth
                    }
                    onResizeEnded(proposedWidth)
                }
        )
        .accessibilityLabel("Resize YAML editor panel")
    }

    private func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, AppState.yamlEditorMinWidth), AppState.yamlEditorMaxWidth)
    }
}

private struct ResizableInspectorDetailView: View {
    let initialWidth: CGFloat
    let onResizeEnded: (CGFloat) -> Void

    @State private var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var isHoveringResizeHandle = false

    init(initialWidth: CGFloat, onResizeEnded: @escaping (CGFloat) -> Void) {
        self.initialWidth = initialWidth
        self.onResizeEnded = onResizeEnded
        let clampedWidth = min(max(initialWidth, AppState.inspectorDetailMinWidth), AppState.inspectorDetailMaxWidth)
        _width = State(initialValue: clampedWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            InspectorDetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.Colors.contentBackground)
        }
        .frame(width: width)
        .onAppear {
            width = clamp(initialWidth)
        }
        .onDisappear {
            if isHoveringResizeHandle {
                NSCursor.pop()
                isHoveringResizeHandle = false
            }
        }
    }

    private var resizeHandle: some View {
        ZStack(alignment: .trailing) {
            Color.clear
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHoveringResizeHandle else { return }

            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            isHoveringResizeHandle = hovering
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }

                    guard let startWidth = dragStartWidth else { return }
                    let proposedWidth = clamp(startWidth - value.translation.width)
                    let snappedWidth = (proposedWidth / 2).rounded() * 2

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = snappedWidth
                    }
                }
                .onEnded { value in
                    defer {
                        dragStartWidth = nil
                    }

                    guard let startWidth = dragStartWidth else {
                        onResizeEnded(width)
                        return
                    }

                    let proposedWidth = clamp(startWidth - value.translation.width)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = proposedWidth
                    }
                    onResizeEnded(proposedWidth)
                }
        )
        .accessibilityLabel("Resize detail panel")
    }

    private func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, AppState.inspectorDetailMinWidth), AppState.inspectorDetailMaxWidth)
    }
}
