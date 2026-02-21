import Foundation

enum ClusterConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

struct ClusterConnection: Identifiable, Sendable, Hashable {
    let id: UUID
    var contextName: String
    var clusterName: String
    var clusterURL: String
    var userName: String
    var status: ClusterConnectionStatus
    var namespaces: [String]
    var currentNamespace: String?
    var serverVersion: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        contextName: String,
        clusterName: String = "",
        clusterURL: String = "",
        userName: String = "",
        status: ClusterConnectionStatus = .disconnected,
        namespaces: [String] = [],
        currentNamespace: String? = nil,
        serverVersion: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.contextName = contextName
        self.clusterName = clusterName
        self.clusterURL = clusterURL
        self.userName = userName
        self.status = status
        self.namespaces = namespaces
        self.currentNamespace = currentNamespace
        self.serverVersion = serverVersion
        self.errorMessage = errorMessage
    }

    var displayName: String {
        contextName.isEmpty ? clusterName : contextName
    }

    var initials: String {
        let name = displayName
        let words = name.split(separator: "-")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
