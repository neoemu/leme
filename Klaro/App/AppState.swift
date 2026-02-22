import SwiftUI

enum SidebarSelection: Hashable, Sendable {
    case dashboard
    case unifiedWorkloads
    case resource(ResourceKind)
}

@Observable
final class AppState: @unchecked Sendable {
    static let inspectorDetailMinWidth: CGFloat = 300
    static let inspectorDetailDefaultWidth: CGFloat = 420
    static let inspectorDetailMaxWidth: CGFloat = 800

    private static let inspectorDetailWidthDefaultsKey = "inspectorDetailWidth"

    var clusters: [ClusterConnection] = []
    var activeClusterID: UUID?
    var selectedNamespace: String?
    var sidebarSelection: SidebarSelection? = .dashboard
    var selectedResourceID: String?
    var isDetailPanelOpen: Bool = false
    private(set) var inspectorDetailWidth: CGFloat = AppState.loadInspectorDetailWidth()
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

    // MARK: - Computed compat properties

    var showDashboard: Bool {
        get { sidebarSelection == .dashboard }
        set {
            if newValue { sidebarSelection = .dashboard }
        }
    }

    var showUnifiedWorkloads: Bool {
        get { sidebarSelection == .unifiedWorkloads }
        set {
            if newValue { sidebarSelection = .unifiedWorkloads }
        }
    }

    var selectedResourceKind: ResourceKind {
        get {
            if case .resource(let kind) = sidebarSelection { return kind }
            return .pod
        }
        set {
            sidebarSelection = .resource(newValue)
        }
    }

    func selectCluster(_ id: UUID) {
        activeClusterID = id
        selectedNamespace = nil
        sidebarSelection = .dashboard
        selectedResourceID = nil
        isDetailPanelOpen = false
    }

    func selectResource(_ id: String?) {
        selectedResourceID = id
    }

    func showResourceDetail(_ id: String) {
        selectedResourceID = id
        isDetailPanelOpen = true
    }

    func openBottomPanel(mode: BottomPanelMode) {
        bottomPanelMode = mode
        isBottomPanelOpen = true
    }

    func setInspectorDetailWidth(_ width: CGFloat, persist: Bool = true) {
        guard width.isFinite, width > 0 else { return }

        let clampedWidth = Self.clampInspectorDetailWidth(width)
        guard abs(clampedWidth - inspectorDetailWidth) >= 0.5 else { return }

        inspectorDetailWidth = clampedWidth
        guard persist else { return }

        UserDefaults.standard.set(
            Double(clampedWidth),
            forKey: Self.inspectorDetailWidthDefaultsKey
        )
    }

    func persistInspectorDetailWidth() {
        UserDefaults.standard.set(
            Double(inspectorDetailWidth),
            forKey: Self.inspectorDetailWidthDefaultsKey
        )
    }

    func updateCluster(_ cluster: ClusterConnection) {
        if let index = clusters.firstIndex(where: { $0.id == cluster.id }) {
            clusters[index] = cluster
        }
    }

    private static func loadInspectorDetailWidth() -> CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: inspectorDetailWidthDefaultsKey) != nil else {
            return inspectorDetailDefaultWidth
        }

        let storedWidth = CGFloat(defaults.double(forKey: inspectorDetailWidthDefaultsKey))
        guard storedWidth.isFinite else { return inspectorDetailDefaultWidth }
        return clampInspectorDetailWidth(storedWidth)
    }

    private static func clampInspectorDetailWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, inspectorDetailMinWidth), inspectorDetailMaxWidth)
    }
}
