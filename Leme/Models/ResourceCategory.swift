import Foundation

enum ResourceCategory: String, CaseIterable, Identifiable, Sendable {
    case cluster = "Cluster"
    case workloads = "Workloads"
    case network = "Network"
    case configuration = "Configuration"
    case storage = "Storage"
    case accessControl = "Access Control"
    case policy = "Policy"
    case events = "Events"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cluster: return "server.rack"
        case .workloads: return "shippingbox"
        case .network: return "network"
        case .configuration: return "gearshape"
        case .storage: return "externaldrive"
        case .accessControl: return "lock.shield"
        case .policy: return "shield.lefthalf.filled"
        case .events: return "bell"
        }
    }

    var resourceKinds: [ResourceKind] {
        ResourceKind.allCases.filter { $0.category == self }
    }
}
