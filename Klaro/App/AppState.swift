import SwiftUI

enum SidebarPlaceholder: String, Hashable, Sendable {
    case projectsNamespaces
    case clusterMembers
    case tools
    case charts
    case installedApps
    case repositories
    case recentOperations
    case moreResources
}

struct CustomResourceNavigationTarget: Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let plural: String
    let group: String
    let version: String
    let scope: String

    init(definition: CustomResourceDefinitionInfo) {
        self.id = definition.id
        self.name = definition.name
        self.kind = definition.kind
        self.plural = definition.plural
        self.group = definition.group
        self.version = definition.version
        self.scope = definition.scope
    }

    var definitionInfo: CustomResourceDefinitionInfo {
        CustomResourceDefinitionInfo(
            id: id,
            name: name,
            kind: kind,
            plural: plural,
            group: group,
            version: version,
            scope: scope,
            shortNames: []
        )
    }

    var displayName: String {
        kind + "s"
    }
}

enum SidebarSelection: Hashable, Sendable {
    case resource(ResourceKind)
    case customResource(CustomResourceNavigationTarget)
    case placeholder(SidebarPlaceholder)
}

@Observable
final class AppState: @unchecked Sendable {
    static let inspectorDetailMinWidth: CGFloat = 300
    static let inspectorDetailDefaultWidth: CGFloat = 420
    static let inspectorDetailMaxWidth: CGFloat = 800

    static let yamlEditorMinWidth: CGFloat = 520
    static let yamlEditorDefaultWidth: CGFloat = 760
    static let yamlEditorMaxWidth: CGFloat = 1300

    private static let inspectorDetailWidthDefaultsKey = "inspectorDetailWidth"
    private static let yamlEditorWidthDefaultsKey = "yamlEditorWidth"

    var clusters: [ClusterConnection] = []
    var activeClusterID: UUID?
    var selectedNamespace: String?
    var sidebarSelection: SidebarSelection? = .resource(.pod)
    var selectedResourceID: String?
    var isDetailPanelOpen: Bool = false
    private(set) var inspectorDetailWidth: CGFloat = AppState.loadInspectorDetailWidth()
    var isYAMLEditorOpen: Bool = false
    var yamlEditorTitle: String = "YAML Editor"
    private(set) var yamlEditorWidth: CGFloat = AppState.loadYAMLEditorWidth()
    var isBottomPanelOpen: Bool = false
    var bottomPanelMode: BottomPanelMode = .logs
    var bottomPanelHeight: CGFloat = 250
    var isCommandPaletteOpen: Bool = false
    var isGlobalSearchOpen: Bool = false
    var searchText: String = ""
    var logTargetPodName: String?
    var logTargetNamespace: String?
    var logTargetContainer: String?
    /// When non-empty, the log request aggregates these pods (workload logs).
    var logTargetPodNames: [String] = []
    var pendingPodLogsRequestID: UUID?

    // Terminal exec target
    var execTargetPodName: String?
    var execTargetNamespace: String?
    var execTargetContainer: String?
    var pendingPodExecRequestID: UUID?

    // YAML editor source
    var yamlSource: String = ""
    var yamlOriginalSource: String = ""

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
        get { false }
        set {
            if newValue { sidebarSelection = .resource(.node) }
        }
    }

    var showUnifiedWorkloads: Bool {
        get { false }
        set {
            if newValue { sidebarSelection = .resource(.pod) }
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

    var selectedCustomResourceTarget: CustomResourceNavigationTarget? {
        guard case .customResource(let target) = sidebarSelection else { return nil }
        return target
    }

    func selectCluster(_ id: UUID) {
        activeClusterID = id
        selectedNamespace = nil
        sidebarSelection = .resource(.pod)
        selectedResourceID = nil
        isDetailPanelOpen = false
        isYAMLEditorOpen = false
    }

    func selectResource(_ id: String?) {
        selectedResourceID = id
    }

    func showResourceDetail(_ id: String) {
        selectedResourceID = id
        isYAMLEditorOpen = false
        isDetailPanelOpen = true
    }

    func showYAMLEditor(resourceID: String?, title: String, yaml: String) {
        if let resourceID {
            selectedResourceID = resourceID
        }
        yamlEditorTitle = title
        yamlSource = yaml
        yamlOriginalSource = yaml
        isBottomPanelOpen = false
        isDetailPanelOpen = false
        isYAMLEditorOpen = true
    }

    func closeYAMLEditor() {
        isYAMLEditorOpen = false
    }

    func openBottomPanel(mode: BottomPanelMode) {
        isYAMLEditorOpen = false
        bottomPanelMode = mode
        isBottomPanelOpen = true
    }

    func requestPodLogs(podName: String, namespace: String, container: String? = nil) {
        logTargetPodName = podName
        logTargetNamespace = namespace
        logTargetContainer = container
        logTargetPodNames = []
        pendingPodLogsRequestID = UUID()
        openBottomPanel(mode: .logs)
    }

    /// Streams logs of all pods of a workload, stern-style.
    func requestWorkloadLogs(workloadName: String, podNames: [String], namespace: String) {
        logTargetPodName = workloadName
        logTargetNamespace = namespace
        logTargetContainer = nil
        logTargetPodNames = podNames
        pendingPodLogsRequestID = UUID()
        openBottomPanel(mode: .logs)
    }

    func requestPodExec(podName: String, namespace: String, container: String? = nil) {
        execTargetPodName = podName
        execTargetNamespace = namespace
        execTargetContainer = container
        pendingPodExecRequestID = UUID()
        openBottomPanel(mode: .terminal)
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

    func setYAMLEditorWidth(_ width: CGFloat, persist: Bool = true) {
        guard width.isFinite, width > 0 else { return }

        let clampedWidth = Self.clampYAMLEditorWidth(width)
        guard abs(clampedWidth - yamlEditorWidth) >= 0.5 else { return }

        yamlEditorWidth = clampedWidth
        guard persist else { return }

        UserDefaults.standard.set(
            Double(clampedWidth),
            forKey: Self.yamlEditorWidthDefaultsKey
        )
    }

    func persistYAMLEditorWidth() {
        UserDefaults.standard.set(
            Double(yamlEditorWidth),
            forKey: Self.yamlEditorWidthDefaultsKey
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

    private static func loadYAMLEditorWidth() -> CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: yamlEditorWidthDefaultsKey) != nil else {
            return yamlEditorDefaultWidth
        }

        let storedWidth = CGFloat(defaults.double(forKey: yamlEditorWidthDefaultsKey))
        guard storedWidth.isFinite else { return yamlEditorDefaultWidth }
        return clampYAMLEditorWidth(storedWidth)
    }

    private static func clampInspectorDetailWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, inspectorDetailMinWidth), inspectorDetailMaxWidth)
    }

    private static func clampYAMLEditorWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, yamlEditorMinWidth), yamlEditorMaxWidth)
    }
}
