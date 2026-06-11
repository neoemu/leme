import Foundation

/// User preferences persisted in UserDefaults, observable by the UI.
@Observable
@MainActor
final class SettingsStore {

    nonisolated static let kubeconfigPathKey = "kubeconfigPath"
    nonisolated static let environmentOverridesKey = "clusterEnvironmentOverrides"
    nonisolated static let autoRefreshIntervalKey = "autoRefreshInterval"

    /// Sentinel stored when the user explicitly removes a cluster's badge.
    nonisolated static let noEnvironmentSentinel = "none"

    var kubeconfigPath: String {
        didSet {
            UserDefaults.standard.set(kubeconfigPath, forKey: Self.kubeconfigPathKey)
        }
    }

    /// Per-cluster environment overrides keyed by context name. Values are
    /// `ClusterEnvironment` raw values or `noEnvironmentSentinel`.
    var environmentOverrides: [String: String] {
        didSet {
            UserDefaults.standard.set(environmentOverrides, forKey: Self.environmentOverridesKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        kubeconfigPath = defaults.string(forKey: Self.kubeconfigPathKey) ?? Constants.defaultKubeconfigPath
        environmentOverrides = defaults.dictionary(forKey: Self.environmentOverridesKey) as? [String: String] ?? [:]
    }

    // MARK: - Environment Resolution

    /// Effective environment for a cluster: manual override wins, otherwise
    /// keyword detection from the context name.
    func environment(for cluster: ClusterConnection) -> ClusterEnvironment? {
        Self.resolveEnvironment(
            override: environmentOverrides[cluster.contextName],
            detectedFrom: cluster.displayName
        )
    }

    func isProduction(_ cluster: ClusterConnection?) -> Bool {
        guard let cluster else { return false }
        return environment(for: cluster) == .production
    }

    /// Sets a manual override. `nil` removes the badge entirely.
    func setEnvironmentOverride(_ environment: ClusterEnvironment?, forContext contextName: String) {
        environmentOverrides[contextName] = environment?.rawValue ?? Self.noEnvironmentSentinel
    }

    /// Returns to automatic keyword detection.
    func clearEnvironmentOverride(forContext contextName: String) {
        environmentOverrides.removeValue(forKey: contextName)
    }

    func hasOverride(forContext contextName: String) -> Bool {
        environmentOverrides[contextName] != nil
    }

    nonisolated static func resolveEnvironment(override: String?, detectedFrom name: String) -> ClusterEnvironment? {
        if let override {
            if override == noEnvironmentSentinel {
                return nil
            }
            return ClusterEnvironment(rawValue: override)
        }
        return ClusterEnvironment.detect(from: name)
    }
}
