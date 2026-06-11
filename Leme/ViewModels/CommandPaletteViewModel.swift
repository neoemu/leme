import SwiftUI
import SwiftkubeModel

struct CommandAction: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let category: String
    let action: @MainActor @Sendable () -> Void
}

@Observable
@MainActor
final class CommandPaletteViewModel {
    var searchText: String = ""
    var actions: [CommandAction] = []
    var selectedIndex: Int = 0

    var filteredActions: [CommandAction] {
        guard !searchText.isEmpty else { return actions }
        let query = searchText.lowercased()
        return actions.filter { action in
            fuzzyMatch(query: query, target: action.title.lowercased())
            || (action.subtitle?.lowercased().contains(query) ?? false)
            || action.category.lowercased().contains(query)
        }
    }

    func buildActions(appState: AppState, clusterViewModel: ClusterViewModel, settingsStore: SettingsStore) {
        var result: [CommandAction] = []

        // Operations on the currently selected resource come first.
        result += selectedResourceActions(
            appState: appState,
            clusterViewModel: clusterViewModel,
            settingsStore: settingsStore
        )

        // Cluster-level operations
        if let activeCluster = appState.activeCluster {
            result.append(CommandAction(
                title: "Disconnect from \(activeCluster.displayName)",
                subtitle: "Close the connection to this cluster",
                icon: "power",
                category: "Cluster"
            ) { [weak appState] in
                guard let appState else { return }
                appState.isCommandPaletteOpen = false
                Task { await clusterViewModel.disconnect(clusterID: activeCluster.id, appState: appState) }
            })
        }

        result.append(CommandAction(
            title: "Reload Kubeconfig",
            subtitle: "Re-read contexts from the kubeconfig file",
            icon: "arrow.clockwise",
            category: "Cluster"
        ) { [weak appState] in
            guard let appState else { return }
            appState.isCommandPaletteOpen = false
            Task { await clusterViewModel.reloadContexts(appState: appState) }
        })

        // Navigate to feature views
        result.append(CommandAction(
            title: "Problems",
            subtitle: "What is broken right now",
            icon: "stethoscope",
            category: "Navigate"
        ) { [weak appState] in
            guard let appState else { return }
            appState.sidebarSelection = .problems
            appState.isCommandPaletteOpen = false
        })

        result.append(CommandAction(
            title: "Installed Apps",
            subtitle: "Helm releases",
            icon: "square.stack.3d.up",
            category: "Navigate"
        ) { [weak appState] in
            guard let appState else { return }
            appState.sidebarSelection = .helmReleases
            appState.isCommandPaletteOpen = false
        })

        result.append(CommandAction(
            title: "Search Resources",
            subtitle: "Global search across all namespaces (⌘K)",
            icon: "magnifyingglass",
            category: "Navigate"
        ) { [weak appState] in
            guard let appState else { return }
            appState.isCommandPaletteOpen = false
            appState.isGlobalSearchOpen = true
        })

        // Navigate to Cluster Overview
        result.append(CommandAction(
            title: "Cluster Overview",
            subtitle: "Navigate to cluster overview",
            icon: "server.rack",
            category: "Navigate"
        ) { [weak appState] in
            guard let appState else { return }
            appState.selectedResourceKind = .node
            appState.isCommandPaletteOpen = false
        })

        result.append(CommandAction(
            title: "More Resources",
            subtitle: "Open grouped resources and CRDs",
            icon: "square.grid.3x3",
            category: "Navigate"
        ) { [weak appState] in
            guard let appState else { return }
            appState.sidebarSelection = .placeholder(.moreResources)
            appState.isCommandPaletteOpen = false
        })

        // Navigate to each ResourceKind
        for kind in ResourceKind.allCases {
            result.append(CommandAction(
                title: kind.pluralName,
                subtitle: kind.category.rawValue,
                icon: kind.icon,
                category: "Navigate"
            ) { [weak appState] in
                guard let appState else { return }
                appState.selectedResourceKind = kind
                appState.isCommandPaletteOpen = false
            })
        }

        // Open Terminal (local shell)
        result.append(CommandAction(
            title: "Open Terminal",
            subtitle: "Open a local shell session",
            icon: "terminal",
            category: "Terminal"
        ) { [weak appState] in
            guard let appState else { return }
            appState.openBottomPanel(mode: .terminal)
            appState.isCommandPaletteOpen = false
        })

        // Open Logs
        result.append(CommandAction(
            title: "Open Logs",
            subtitle: "View pod logs",
            icon: "doc.text.magnifyingglass",
            category: "Action"
        ) { [weak appState] in
            guard let appState else { return }
            appState.openBottomPanel(mode: .logs)
            appState.isCommandPaletteOpen = false
        })

        // Toggle Detail Panel
        result.append(CommandAction(
            title: "Toggle Detail Panel",
            subtitle: "Show or hide the detail panel",
            icon: "sidebar.trailing",
            category: "Action"
        ) { [weak appState] in
            guard let appState else { return }
            if appState.isYAMLEditorOpen {
                appState.closeYAMLEditor()
            } else {
                appState.isDetailPanelOpen.toggle()
            }
            appState.isCommandPaletteOpen = false
        })

        // Close Bottom Panel
        result.append(CommandAction(
            title: "Close Bottom Panel",
            subtitle: "Dismiss the bottom panel",
            icon: "rectangle.bottomthird.inset.filled",
            category: "Action"
        ) { [weak appState] in
            guard let appState else { return }
            appState.isBottomPanelOpen = false
            appState.isCommandPaletteOpen = false
        })

        // Switch to each connected cluster
        for cluster in appState.clusters where cluster.status == .connected {
            result.append(CommandAction(
                title: "Switch to \(cluster.displayName)",
                subtitle: cluster.clusterURL,
                icon: "circle.fill",
                category: "Cluster"
            ) { [weak appState] in
                guard let appState else { return }
                appState.selectCluster(cluster.id)
                appState.isCommandPaletteOpen = false
            })
        }

        actions = result
        selectedIndex = 0
        searchText = ""
    }

    func executeSelected(appState: AppState) {
        let filtered = filteredActions
        guard !filtered.isEmpty, selectedIndex >= 0, selectedIndex < filtered.count else { return }
        filtered[selectedIndex].action()
    }

    func moveUp() {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    func moveDown() {
        let count = filteredActions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    // MARK: - Selected resource operations

    /// Operational commands for the currently selected resource. Destructive
    /// operations on production clusters route through the shared
    /// type-to-confirm sheet (hosted by MainLayout, since the palette closes
    /// before the confirmation shows).
    private func selectedResourceActions(
        appState: AppState,
        clusterViewModel: ClusterViewModel,
        settingsStore: SettingsStore
    ) -> [CommandAction] {
        guard case .resource(let kind) = appState.sidebarSelection,
              let resourceID = appState.selectedResourceID else { return [] }

        let parts = resourceID.split(separator: "/", maxSplits: 1)
        let name: String
        let namespace: String?
        if kind.isNamespaced {
            guard parts.count == 2 else { return [] }
            namespace = String(parts[0])
            name = String(parts[1])
        } else {
            name = parts.count == 2 ? String(parts[1]) : String(parts[0])
            namespace = nil
        }

        let isProduction = settingsStore.isProduction(appState.activeCluster)
        let category = "Selected \(kind.rawValue)"
        var result: [CommandAction] = []

        func run(_ description: String, _ operation: @escaping @Sendable (KubernetesService) async throws -> Void) {
            Self.runOperation(description, appState: appState, clusterViewModel: clusterViewModel, operation: operation)
        }

        /// Closes the palette and either runs directly or, on production,
        /// asks for type-to-confirm first.
        func gatedAction(
            title: String,
            message: String,
            confirmLabel: String,
            description: String,
            operation: @escaping @Sendable (KubernetesService) async throws -> Void
        ) -> @MainActor @Sendable () -> Void {
            { [weak appState] in
                guard let appState else { return }
                appState.isCommandPaletteOpen = false
                if isProduction {
                    appState.pendingDangerAction = PendingDangerAction(
                        title: title,
                        message: message,
                        confirmText: name,
                        confirmLabel: confirmLabel
                    ) {
                        run(description, operation)
                    }
                } else {
                    run(description, operation)
                }
            }
        }

        switch kind {
        case .pod:
            result.append(CommandAction(
                title: "View Logs: \(name)",
                subtitle: namespace,
                icon: "doc.text.magnifyingglass",
                category: category
            ) { [weak appState] in
                guard let appState else { return }
                appState.requestPodLogs(podName: name, namespace: namespace ?? "default")
                appState.isCommandPaletteOpen = false
            })

            result.append(CommandAction(
                title: "Open Shell: \(name)",
                subtitle: namespace,
                icon: "terminal",
                category: category
            ) { [weak appState] in
                guard let appState else { return }
                appState.requestPodExec(podName: name, namespace: namespace ?? "default")
                appState.isCommandPaletteOpen = false
            })

            result.append(CommandAction(
                title: "Delete Pod: \(name)",
                subtitle: namespace,
                icon: "trash",
                category: category,
                action: gatedAction(
                    title: "Delete \(name)",
                    message: "This permanently deletes pod \(name) from a production cluster.",
                    confirmLabel: "Delete",
                    description: "Delete pod \(name)"
                ) { service in
                    try await service.delete(core.v1.Pod.self, name: name, in: namespace)
                }
            ))

        case .deployment, .statefulSet, .daemonSet:
            result.append(CommandAction(
                title: "Restart \(kind.rawValue): \(name)",
                subtitle: namespace,
                icon: "arrow.clockwise",
                category: category,
                action: gatedAction(
                    title: "Restart \(name)",
                    message: "This triggers a rolling restart of all pods of \(name) on a production cluster.",
                    confirmLabel: "Restart",
                    description: "Restart \(kind.rawValue.lowercased()) \(name)"
                ) { service in
                    switch kind {
                    case .deployment:
                        try await service.restartDeployment(name: name, in: namespace)
                    case .statefulSet:
                        try await service.restartStatefulSet(name: name, in: namespace)
                    default:
                        try await service.restartDaemonSet(name: name, in: namespace)
                    }
                }
            ))

            let rolloutArgument = "\(kind.rawValue.lowercased())/\(name)"
            result.append(CommandAction(
                title: "Rollback \(kind.rawValue): \(name)",
                subtitle: "Rollout undo to the previous revision",
                icon: "clock.arrow.circlepath",
                category: category,
                action: gatedAction(
                    title: "Rollback \(name)",
                    message: "This rolls \(name) back to its previous revision on a production cluster.",
                    confirmLabel: "Rollback",
                    description: "Rollback \(kind.rawValue.lowercased()) \(name)"
                ) { service in
                    _ = try await service.rolloutUndo(resourceArgument: rolloutArgument, in: namespace)
                }
            ))

        case .node:
            result.append(CommandAction(
                title: "Cordon Node: \(name)",
                subtitle: "Mark as unschedulable",
                icon: "nosign",
                category: category
            ) { [weak appState] in
                guard let appState else { return }
                appState.isCommandPaletteOpen = false
                run("Cordon node \(name)") { service in
                    try await service.setNodeUnschedulable(name: name, unschedulable: true)
                }
            })

            result.append(CommandAction(
                title: "Uncordon Node: \(name)",
                subtitle: "Mark as schedulable again",
                icon: "checkmark.circle",
                category: category
            ) { [weak appState] in
                guard let appState else { return }
                appState.isCommandPaletteOpen = false
                run("Uncordon node \(name)") { service in
                    try await service.setNodeUnschedulable(name: name, unschedulable: false)
                }
            })

            result.append(CommandAction(
                title: "Drain Node: \(name)",
                subtitle: "Cordon and evict all pods",
                icon: "arrow.down.right.and.arrow.up.left",
                category: category,
                action: gatedAction(
                    title: "Drain \(name)",
                    message: "This cordons \(name) and evicts every pod on it (production cluster).",
                    confirmLabel: "Drain",
                    description: "Drain node \(name)"
                ) { service in
                    _ = try await service.drainNode(name: name)
                }
            ))

        default:
            break
        }

        return result
    }

    private static func runOperation(
        _ description: String,
        appState: AppState,
        clusterViewModel: ClusterViewModel,
        operation: @escaping @Sendable (KubernetesService) async throws -> Void
    ) {
        Task { @MainActor in
            guard let client = try? await clusterViewModel.clientForActiveCluster(appState: appState) else {
                appState.showToast("\(description): no active cluster connection")
                return
            }
            let service = KubernetesService(client: client, contextName: appState.activeCluster?.contextName)
            do {
                appState.showToast("\(description)…")
                try await operation(service)
                appState.showToast("\(description) — done")
            } catch {
                appState.showToast("\(description) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Fuzzy matching

    private func fuzzyMatch(query: String, target: String) -> Bool {
        var targetIndex = target.startIndex
        for char in query {
            guard let found = target[targetIndex...].firstIndex(of: char) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }
}
