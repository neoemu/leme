import Foundation
import SwiftkubeClient
import SwiftkubeModel

/// One thing that is broken (or degraded) in the cluster right now.
struct ProblemItem: Identifiable, Sendable, Hashable {
    enum Severity: Int, Sendable, Comparable {
        case critical = 0
        case warning = 1

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let severity: Severity
    let kind: ResourceKind
    let name: String
    let namespace: String?
    /// Short reason, e.g. "CrashLoopBackOff", "NotReady", "Degraded".
    let title: String
    let detail: String
    let age: Date?

    var id: String { "\(kind.rawValue)/\(namespace ?? "")/\(name)/\(title)" }

    /// Matches `involvedObject` references in events ("Kind/namespace/name").
    var eventKey: String { "\(kind.rawValue)/\(namespace ?? "")/\(name)" }
}

/// A recent Warning event correlated to a problem item.
struct ProblemEvent: Identifiable, Sendable, Hashable {
    let id: String
    let reason: String
    let message: String
    let count: Int
    let lastSeen: Date?
}

@Observable
@MainActor
final class ProblemsViewModel {
    var problems: [ProblemItem] = []
    var eventsByTarget: [String: [ProblemEvent]] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    var criticalCount: Int { problems.lazy.filter { $0.severity == .critical }.count }
    var warningCount: Int { problems.lazy.filter { $0.severity == .warning }.count }

    func load(client: KubernetesClient, namespace: String?, contextName: String?, showSpinner: Bool = true) async {
        if showSpinner {
            isLoading = true
        }
        defer {
            if showSpinner {
                isLoading = false
            }
        }

        let service = KubernetesService(client: client, contextName: contextName)

        do {
            async let pods = service.list(core.v1.Pod.self, in: namespace)
            async let deployments = service.list(apps.v1.Deployment.self, in: namespace)
            async let statefulSets = service.list(apps.v1.StatefulSet.self, in: namespace)
            async let daemonSets = service.list(apps.v1.DaemonSet.self, in: namespace)
            async let jobs = service.list(batch.v1.Job.self, in: namespace)
            async let pvcs = service.list(core.v1.PersistentVolumeClaim.self, in: namespace)
            async let nodes = service.listClusterScoped(core.v1.Node.self)
            async let events = service.list(core.v1.Event.self, in: namespace)

            var items: [ProblemItem] = []
            items += try await pods.items.flatMap(Self.problems(fromPod:))
            items += try await deployments.items.flatMap(Self.problems(fromDeployment:))
            items += try await statefulSets.items.flatMap(Self.problems(fromStatefulSet:))
            items += try await daemonSets.items.flatMap(Self.problems(fromDaemonSet:))
            items += try await jobs.items.flatMap(Self.problems(fromJob:))
            items += try await pvcs.items.flatMap(Self.problems(fromPVC:))
            items += try await nodes.items.flatMap(Self.problems(fromNode:))

            problems = items.sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity < rhs.severity
                }
                if lhs.kind != rhs.kind {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.name < rhs.name
            }
            eventsByTarget = Self.warningEvents(from: try await events.items)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func events(for item: ProblemItem) -> [ProblemEvent] {
        eventsByTarget[item.eventKey] ?? []
    }

    // MARK: - Detection rules (pure, testable)

    nonisolated static func problems(fromPod pod: core.v1.Pod) -> [ProblemItem] {
        guard let name = pod.metadata?.name else { return [] }
        // Terminating pods churn through transient states; not actionable.
        guard pod.metadata?.deletionTimestamp == nil else { return [] }

        let namespace = pod.metadata?.namespace
        let age = pod.metadata?.creationTimestamp
        let phase = pod.status?.phase ?? ""
        guard phase != "Succeeded" else { return [] }

        var items: [ProblemItem] = []
        func add(_ severity: ProblemItem.Severity, _ title: String, _ detail: String) {
            items.append(ProblemItem(
                severity: severity, kind: .pod, name: name, namespace: namespace,
                title: title, detail: detail, age: age
            ))
        }

        if phase == "Failed" {
            add(.critical, pod.status?.reason ?? "Failed", pod.status?.message ?? "Pod is in Failed phase.")
            return items
        }

        if phase == "Pending",
           let scheduled = pod.status?.conditions?.first(where: { $0.type == "PodScheduled" && $0.status == "False" }) {
            add(.critical, scheduled.reason ?? "Unschedulable", scheduled.message ?? "Pod cannot be scheduled.")
        }

        let errorWaitingReasons: Set<String> = [
            "CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull", "ErrImageNeverPull",
            "CreateContainerConfigError", "CreateContainerError", "InvalidImageName", "RunContainerError",
        ]

        let containerStatuses = (pod.status?.containerStatuses ?? []) + (pod.status?.initContainerStatuses ?? [])
        for status in containerStatuses {
            if let waiting = status.state?.waiting, let reason = waiting.reason, errorWaitingReasons.contains(reason) {
                add(.critical, reason, "Container \(status.name): \(waiting.message ?? "waiting") (restarts: \(status.restartCount))")
            } else if let terminated = status.lastState?.terminated, terminated.reason == "OOMKilled" {
                add(.warning, "OOMKilled", "Container \(status.name) was OOM-killed (restarts: \(status.restartCount)).")
            } else if status.restartCount >= 5 {
                add(.warning, "High Restarts", "Container \(status.name) restarted \(status.restartCount) times.")
            }
        }

        if items.isEmpty, phase == "Running",
           let ready = pod.status?.conditions?.first(where: { $0.type == "Ready" }),
           ready.status == "False" {
            add(.warning, "Not Ready", ready.message ?? "Pod is running but not passing readiness.")
        }

        // A pod stuck Pending without a scheduling condition is still a problem.
        if items.isEmpty, phase == "Pending" {
            add(.warning, "Pending", pod.status?.message ?? "Pod is pending.")
        }

        return items
    }

    nonisolated static func problems(fromDeployment deployment: apps.v1.Deployment) -> [ProblemItem] {
        guard let name = deployment.metadata?.name else { return [] }
        let desired = deployment.spec?.replicas ?? 1
        guard desired > 0 else { return [] }
        let ready = deployment.status?.readyReplicas ?? 0
        guard ready < desired else { return [] }

        var detail = "\(ready)/\(desired) replicas ready"
        if let progressing = deployment.status?.conditions?.first(where: { $0.type == "Progressing" && $0.status == "False" }) {
            detail += " — \(progressing.reason ?? "progress deadline exceeded")"
        }

        return [ProblemItem(
            severity: ready == 0 ? .critical : .warning,
            kind: .deployment,
            name: name,
            namespace: deployment.metadata?.namespace,
            title: ready == 0 ? "Unavailable" : "Degraded",
            detail: detail,
            age: deployment.metadata?.creationTimestamp
        )]
    }

    nonisolated static func problems(fromStatefulSet statefulSet: apps.v1.StatefulSet) -> [ProblemItem] {
        guard let name = statefulSet.metadata?.name else { return [] }
        let desired = statefulSet.spec?.replicas ?? 1
        guard desired > 0 else { return [] }
        let ready = statefulSet.status?.readyReplicas ?? 0
        guard ready < desired else { return [] }

        return [ProblemItem(
            severity: ready == 0 ? .critical : .warning,
            kind: .statefulSet,
            name: name,
            namespace: statefulSet.metadata?.namespace,
            title: ready == 0 ? "Unavailable" : "Degraded",
            detail: "\(ready)/\(desired) replicas ready",
            age: statefulSet.metadata?.creationTimestamp
        )]
    }

    nonisolated static func problems(fromDaemonSet daemonSet: apps.v1.DaemonSet) -> [ProblemItem] {
        guard let name = daemonSet.metadata?.name else { return [] }
        let desired = daemonSet.status?.desiredNumberScheduled ?? 0
        guard desired > 0 else { return [] }
        let ready = daemonSet.status?.numberReady ?? 0
        guard ready < desired else { return [] }

        return [ProblemItem(
            severity: ready == 0 ? .critical : .warning,
            kind: .daemonSet,
            name: name,
            namespace: daemonSet.metadata?.namespace,
            title: ready == 0 ? "Unavailable" : "Degraded",
            detail: "\(ready)/\(desired) pods ready",
            age: daemonSet.metadata?.creationTimestamp
        )]
    }

    nonisolated static func problems(fromJob job: batch.v1.Job) -> [ProblemItem] {
        guard let name = job.metadata?.name else { return [] }
        guard let failed = job.status?.conditions?.first(where: { $0.type == "Failed" && $0.status == "True" }) else {
            return []
        }

        return [ProblemItem(
            severity: .warning,
            kind: .job,
            name: name,
            namespace: job.metadata?.namespace,
            title: "Failed",
            detail: failed.message ?? failed.reason ?? "Job failed.",
            age: job.metadata?.creationTimestamp
        )]
    }

    nonisolated static func problems(fromPVC pvc: core.v1.PersistentVolumeClaim) -> [ProblemItem] {
        guard let name = pvc.metadata?.name else { return [] }
        let phase = pvc.status?.phase ?? ""

        switch phase {
        case "Pending":
            return [ProblemItem(
                severity: .warning, kind: .persistentVolumeClaim, name: name,
                namespace: pvc.metadata?.namespace,
                title: "Pending", detail: "PVC is not bound to a volume.",
                age: pvc.metadata?.creationTimestamp
            )]
        case "Lost":
            return [ProblemItem(
                severity: .critical, kind: .persistentVolumeClaim, name: name,
                namespace: pvc.metadata?.namespace,
                title: "Lost", detail: "PVC lost its underlying volume.",
                age: pvc.metadata?.creationTimestamp
            )]
        default:
            return []
        }
    }

    nonisolated static func problems(fromNode node: core.v1.Node) -> [ProblemItem] {
        guard let name = node.metadata?.name else { return [] }
        let conditions = node.status?.conditions ?? []
        var items: [ProblemItem] = []

        if let ready = conditions.first(where: { $0.type == "Ready" }), ready.status != "True" {
            items.append(ProblemItem(
                severity: .critical, kind: .node, name: name, namespace: nil,
                title: "NotReady",
                detail: ready.message ?? "Node is not ready.",
                age: node.metadata?.creationTimestamp
            ))
        }

        for pressure in ["MemoryPressure", "DiskPressure", "PIDPressure"] {
            if let condition = conditions.first(where: { $0.type == pressure }), condition.status == "True" {
                items.append(ProblemItem(
                    severity: .warning, kind: .node, name: name, namespace: nil,
                    title: pressure,
                    detail: condition.message ?? "Node is under \(pressure).",
                    age: node.metadata?.creationTimestamp
                ))
            }
        }

        return items
    }

    nonisolated static func warningEvents(from events: [core.v1.Event]) -> [String: [ProblemEvent]] {
        var map: [String: [ProblemEvent]] = [:]

        for event in events where event.type == "Warning" {
            guard let kind = event.involvedObject.kind, let name = event.involvedObject.name else { continue }
            let key = "\(kind)/\(event.involvedObject.namespace ?? "")/\(name)"
            map[key, default: []].append(ProblemEvent(
                // See core.v1.Event.objectMeta: `event.metadata?.x` is always nil.
                id: event.objectMeta.name ?? "\(key)-\(event.reason ?? "")",
                reason: event.reason ?? "Warning",
                message: event.message ?? "",
                count: Int(event.count ?? 1),
                lastSeen: event.lastTimestamp ?? event.objectMeta.creationTimestamp
            ))
        }

        for key in map.keys {
            map[key] = Array(
                map[key]!
                    .sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
                    .prefix(5)
            )
        }

        return map
    }
}
