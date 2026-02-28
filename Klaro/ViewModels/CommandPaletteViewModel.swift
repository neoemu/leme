import SwiftUI

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

    func buildActions(appState: AppState) {
        var result: [CommandAction] = []

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
