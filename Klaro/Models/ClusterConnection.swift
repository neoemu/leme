import Foundation

enum ClusterConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

enum ClusterEnvironment: String, Sendable {
    case production = "PROD"
    case staging = "STG"
    case development = "DEV"
    case test = "TEST"

    static func detect(from name: String) -> ClusterEnvironment? {
        let lowered = name.lowercased()
        if lowered.contains("prod") || lowered.contains("prd") {
            return .production
        }
        if lowered.contains("stag") || lowered.contains("stg")
            || lowered.contains("hml") || lowered.contains("homolog") {
            return .staging
        }
        if lowered.contains("dev") {
            return .development
        }
        if lowered.contains("test") || lowered.contains("qa") {
            return .test
        }
        return nil
    }
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

    var environment: ClusterEnvironment? {
        ClusterEnvironment.detect(from: displayName)
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
