import Foundation

enum Constants {
    static let appName = "Klaro"
    static let defaultKubeconfigPath = "~/.kube/config"
    static let clusterConnectTimeout: TimeInterval = 10.0
    static let watchReconnectBaseDelay: TimeInterval = 1.0
    static let watchReconnectMaxDelay: TimeInterval = 30.0
    static let logBufferMaxLines = 10_000
    static let resourceRefreshInterval: TimeInterval = 30.0
    static let searchDebounceInterval: TimeInterval = 0.3
    static let minWindowWidth: CGFloat = 1000
    static let minWindowHeight: CGFloat = 600
    static let defaultWindowWidth: CGFloat = 1400
    static let defaultWindowHeight: CGFloat = 900
}
