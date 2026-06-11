import Foundation
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

@Test func stableUUIDDerivation() {
    #expect(UUID(stableFrom: "ctx-a") == UUID(stableFrom: "ctx-a"))
    #expect(UUID(stableFrom: "ctx-a") != UUID(stableFrom: "ctx-b"))
    // Well-formed RFC 4122 variant: version nibble 5, variant bits 10xx
    let uuid = UUID(stableFrom: "ctx-a").uuidString
    #expect(uuid.split(separator: "-")[2].first == "5")
}

@Test func environmentOverrideResolution() {
    // Override wins over detection
    #expect(SettingsStore.resolveEnvironment(override: "STG", detectedFrom: "g4-prod") == .staging)
    // Sentinel removes the badge even when detection would find one
    #expect(SettingsStore.resolveEnvironment(override: "none", detectedFrom: "g4-prod") == nil)
    // No override falls back to detection
    #expect(SettingsStore.resolveEnvironment(override: nil, detectedFrom: "g4-prod") == .production)
    #expect(SettingsStore.resolveEnvironment(override: nil, detectedFrom: "plain-cluster") == nil)
}

@Test func clusterEnvironmentDetection() {
    #expect(ClusterEnvironment.detect(from: "g4-prod-east") == .production)
    #expect(ClusterEnvironment.detect(from: "g4-staging") == .staging)
    #expect(ClusterEnvironment.detect(from: "hml-cluster") == .staging)
    #expect(ClusterEnvironment.detect(from: "g3-dev") == .development)
    #expect(ClusterEnvironment.detect(from: "qa-cluster") == .test)
    #expect(ClusterEnvironment.detect(from: "g4-east") == nil)
}

@Test func dateRelativeAge() {
    // Evaluate once: relativeAge recomputes against a fresh Date() per access,
    // so two evaluations can straddle the "just now"/"0s" boundary.
    let nowAge = Date().relativeAge
    #expect(nowAge.hasSuffix("s") || nowAge == "just now")

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

@Test func kubernetesErrorClassificationByDetail() {
    #expect(
        KubernetesService.classifyOperationError(
            detail: "Error from server (Forbidden): deployments.apps is forbidden"
        ) == .rbac
    )

    #expect(
        KubernetesService.classifyOperationError(
            detail: "Unable to connect to the server: dial tcp 10.0.0.1:443: i/o timeout"
        ) == .connectivity
    )

    #expect(
        KubernetesService.classifyOperationError(
            detail: "error validating data: ValidationError(Deployment.spec): unknown field"
        ) == .validation
    )
}

@Test func helmReleaseListParsing() throws {
    // `helm list -o json`: revision comes as a string, updated in Go time.String() form.
    let json = """
    [{"name":"ingress-nginx","namespace":"ingress","revision":"12","updated":"2026-05-09 14:21:11.123456 -0300 -03","status":"deployed","chart":"ingress-nginx-4.10.0","app_version":"1.10.0"}]
    """
    let releases = try HelmService.parseReleases(json)
    #expect(releases.count == 1)
    let release = releases[0]
    #expect(release.name == "ingress-nginx")
    #expect(release.namespace == "ingress")
    #expect(release.revision == 12)
    #expect(release.chart == "ingress-nginx-4.10.0")
    #expect(release.appVersion == "1.10.0")
    #expect(release.id == "ingress/ingress-nginx")
    #expect(release.displayStatus == "Deployed")
    #expect(release.updated != nil)
}

@Test func helmEmptyReleaseListParsing() throws {
    #expect(try HelmService.parseReleases("").isEmpty)
    #expect(try HelmService.parseReleases("[]").isEmpty)
}

@Test func helmHistoryParsing() throws {
    // `helm history -o json`: revision comes as a number, updated as RFC 3339.
    let json = """
    [{"revision":1,"updated":"2026-05-09T14:21:11.123456789-03:00","status":"superseded","chart":"app-1.0.0","app_version":"1.0","description":"Install complete"},
     {"revision":2,"updated":"2026-06-01T08:00:00Z","status":"deployed","chart":"app-1.1.0","app_version":"1.1","description":"Upgrade complete"}]
    """
    let revisions = try HelmService.parseHistory(json)
    #expect(revisions.count == 2)
    #expect(revisions[0].revision == 1)
    #expect(revisions[0].updated != nil)
    #expect(revisions[1].status == "deployed")
    #expect(revisions[1].description == "Upgrade complete")
    #expect(revisions[1].updated != nil)
}

@Test func helmTimestampParsing() {
    // Go time.String() with nanoseconds and duplicated zone token
    #expect(HelmTimestampParser.parse("2026-05-09 14:21:11.123456789 -0300 -03") != nil)
    // Go time.String() with UTC abbreviation
    #expect(HelmTimestampParser.parse("2026-05-09 14:21:11.123456 +0000 UTC") != nil)
    // RFC 3339 without fraction
    #expect(HelmTimestampParser.parse("2026-06-01T08:00:00Z") != nil)
    // Garbage and empty input
    #expect(HelmTimestampParser.parse("") == nil)
    #expect(HelmTimestampParser.parse("not-a-date") == nil)

    // Offset must be honored: 12:00 at -03:00 is 15:00 UTC.
    let parsed = HelmTimestampParser.parse("2026-05-09 12:00:00 -0300 -03")
    let reference = ISO8601DateFormatter().date(from: "2026-05-09T15:00:00Z")
    #expect(parsed == reference)
}

@Test func kubernetesErrorClassificationByError() {
    let rbac = KubernetesOperationError(
        category: .rbac,
        detail: "deployments.apps is forbidden"
    )
    #expect(KubernetesService.classifyOperationError(rbac) == .rbac)
}
