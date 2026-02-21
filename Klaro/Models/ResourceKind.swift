import Foundation

enum ResourceKind: String, CaseIterable, Identifiable, Sendable, Hashable {
    // Cluster
    case node = "Node"
    case namespace = "Namespace"

    // Workloads
    case pod = "Pod"
    case deployment = "Deployment"
    case statefulSet = "StatefulSet"
    case daemonSet = "DaemonSet"
    case job = "Job"
    case cronJob = "CronJob"
    case replicaSet = "ReplicaSet"

    // Network
    case service = "Service"
    case ingress = "Ingress"
    case endpoint = "Endpoint"
    case networkPolicy = "NetworkPolicy"

    // Configuration
    case configMap = "ConfigMap"
    case secret = "Secret"

    // Storage
    case persistentVolumeClaim = "PersistentVolumeClaim"
    case persistentVolume = "PersistentVolume"
    case storageClass = "StorageClass"

    // Access Control
    case serviceAccount = "ServiceAccount"
    case role = "Role"
    case clusterRole = "ClusterRole"
    case roleBinding = "RoleBinding"
    case clusterRoleBinding = "ClusterRoleBinding"

    // Events
    case event = "Event"

    var id: String { rawValue }

    var category: ResourceCategory {
        switch self {
        case .node, .namespace:
            return .cluster
        case .pod, .deployment, .statefulSet, .daemonSet, .job, .cronJob, .replicaSet:
            return .workloads
        case .service, .ingress, .endpoint, .networkPolicy:
            return .network
        case .configMap, .secret:
            return .configuration
        case .persistentVolumeClaim, .persistentVolume, .storageClass:
            return .storage
        case .serviceAccount, .role, .clusterRole, .roleBinding, .clusterRoleBinding:
            return .accessControl
        case .event:
            return .events
        }
    }

    var icon: String {
        switch self {
        case .node: return "desktopcomputer"
        case .namespace: return "folder"
        case .pod: return "shippingbox"
        case .deployment: return "arrow.triangle.2.circlepath"
        case .statefulSet: return "square.stack.3d.up"
        case .daemonSet: return "circle.grid.3x3"
        case .job: return "play.rectangle"
        case .cronJob: return "clock.arrow.2.circlepath"
        case .replicaSet: return "square.on.square"
        case .service: return "network"
        case .ingress: return "arrow.right.to.line"
        case .endpoint: return "point.3.connected.trianglepath.dotted"
        case .networkPolicy: return "shield.checkered"
        case .configMap: return "doc.text"
        case .secret: return "lock"
        case .persistentVolumeClaim: return "externaldrive"
        case .persistentVolume: return "internaldrive"
        case .storageClass: return "cylinder"
        case .serviceAccount: return "person.circle"
        case .role: return "person.badge.key"
        case .clusterRole: return "person.badge.shield.checkmark"
        case .roleBinding: return "link.circle"
        case .clusterRoleBinding: return "link.badge.plus"
        case .event: return "bell"
        }
    }

    var pluralName: String {
        switch self {
        case .ingress: return "Ingresses"
        case .endpoint: return "Endpoints"
        case .namespace: return "Namespaces"
        case .storageClass: return "Storage Classes"
        case .networkPolicy: return "Network Policies"
        case .persistentVolumeClaim: return "Persistent Volume Claims"
        case .persistentVolume: return "Persistent Volumes"
        case .configMap: return "Config Maps"
        case .serviceAccount: return "Service Accounts"
        case .clusterRole: return "Cluster Roles"
        case .roleBinding: return "Role Bindings"
        case .clusterRoleBinding: return "Cluster Role Bindings"
        case .statefulSet: return "Stateful Sets"
        case .daemonSet: return "Daemon Sets"
        case .cronJob: return "Cron Jobs"
        case .replicaSet: return "Replica Sets"
        default: return rawValue + "s"
        }
    }

    var isNamespaced: Bool {
        switch self {
        case .node, .namespace, .persistentVolume, .storageClass, .clusterRole, .clusterRoleBinding:
            return false
        default:
            return true
        }
    }
}
