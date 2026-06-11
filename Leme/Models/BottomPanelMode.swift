import Foundation

enum BottomPanelMode: String, Identifiable, Sendable, Hashable {
    case logs = "Logs"
    case terminal = "Terminal"
    case yaml = "YAML"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .logs: return "doc.text.magnifyingglass"
        case .terminal: return "terminal"
        case .yaml: return "doc.plaintext"
        }
    }
}
