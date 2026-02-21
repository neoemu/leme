import Testing
@testable import Klaro

@Test func appStateDefaults() {
    let state = AppState()
    #expect(state.clusters.isEmpty)
    #expect(state.activeClusterID == nil)
    #expect(state.selectedResourceKind == .pod)
    #expect(!state.isBottomPanelOpen)
}

@Test func clusterConnectionInitials() {
    let conn = ClusterConnection(contextName: "my-cluster")
    #expect(conn.initials == "MC")

    let conn2 = ClusterConnection(contextName: "prod-east")
    #expect(conn2.initials == "PE")
}

@Test func dateRelativeAge() {
    let now = Date()
    #expect(now.relativeAge.hasSuffix("s") || now.relativeAge == "just now")

    let fiveMinAgo = Date(timeIntervalSinceNow: -300)
    #expect(fiveMinAgo.relativeAge == "5m")

    let twoDaysAgo = Date(timeIntervalSinceNow: -172800)
    #expect(twoDaysAgo.relativeAge == "2d")
}

@Test func resourceKindCategories() {
    #expect(ResourceKind.pod.category == .workloads)
    #expect(ResourceKind.service.category == .network)
    #expect(ResourceKind.configMap.category == .configuration)
    #expect(ResourceKind.node.category == .cluster)
    #expect(ResourceKind.persistentVolumeClaim.category == .storage)
    #expect(ResourceKind.serviceAccount.category == .accessControl)
    #expect(ResourceKind.event.category == .events)
}
