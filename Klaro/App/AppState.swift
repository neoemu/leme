import SwiftUI

@Observable
final class AppState: @unchecked Sendable {
    var clusters: [ClusterConnection] = []
    var activeClusterID: UUID?
    var selectedNamespace: String?
    var selectedResourceKind: ResourceKind = .pod
    var selectedResourceID: String?
    var isDetailPanelOpen: Bool = false
    var showDashboard: Bool = true
    var showUnifiedWorkloads: Bool = false
    var isBottomPanelOpen: Bool = false
    var bottomPanelMode: BottomPanelMode = .logs
    var bottomPanelHeight: CGFloat = 250
    var isCommandPaletteOpen: Bool = false
    var searchText: String = ""
    var logTargetPodName: String?
    var logTargetNamespace: String?
    var logTargetContainer: String?

    // Terminal exec target
    var execTargetPodName: String?
    var execTargetNamespace: String?
    var execTargetContainer: String?

    // YAML editor source
    var yamlSource: String = ""

    var activeCluster: ClusterConnection? {
        get {
            guard let id = activeClusterID else { return nil }
            return clusters.first { $0.id == id }
        }
        set {
            guard let newValue, let index = clusters.firstIndex(where: { $0.id == newValue.id }) else { return }
            clusters[index] = newValue
        }
    }

    var availableNamespaces: [String] {
        activeCluster?.namespaces ?? []
    }

    var filteredNamespace: String? {
        selectedNamespace
    }

    func selectCluster(_ id: UUID) {
        activeClusterID = id
        selectedNamespace = nil
        selectedResourceKind = .pod
        selectedResourceID = nil
        isDetailPanelOpen = false
        showDashboard = true
        showUnifiedWorkloads = false
    }

    func selectResource(_ id: String?) {
        selectedResourceID = id
        isDetailPanelOpen = id != nil
    }

    func openBottomPanel(mode: BottomPanelMode) {
        bottomPanelMode = mode
        isBottomPanelOpen = true
    }

    func updateCluster(_ cluster: ClusterConnection) {
        if let index = clusters.firstIndex(where: { $0.id == cluster.id }) {
            clusters[index] = cluster
        }
    }
}
