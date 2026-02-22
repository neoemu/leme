import AppKit
import SwiftUI

struct MainLayout: View {
    @Environment(AppState.self) private var appState
    @Environment(ClusterViewModel.self) private var clusterViewModel

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                ContentAreaView()

                if appState.isBottomPanelOpen {
                    BottomPanelView()
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: appState.isBottomPanelOpen)
            .overlay {
                if appState.isDetailPanelOpen {
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
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await clusterViewModel.loadContexts(appState: appState)
                    }
                } label: {
                    Label("Reload Kubeconfig", systemImage: "arrow.clockwise")
                }
                .help("Reload kubeconfig")

                Button {
                    appState.isDetailPanelOpen.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle inspector panel")

                Button {
                    // Settings action placeholder
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Settings")
            }
        }
        .overlay {
            if appState.isCommandPaletteOpen {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isCommandPaletteOpen)
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
                .background(.regularMaterial)
        }
        .frame(width: width)
        .glassEffect(.regular, in: Rectangle())
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
                .fill(Theme.Colors.separator.opacity(0.45))
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
            DragGesture(minimumDistance: 1)
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
