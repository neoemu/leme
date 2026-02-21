import SwiftUI

enum Theme {
    // MARK: - Colors

    enum Colors {
        // Backgrounds
        static let hotbarBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)
        static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
        static let contentBackground = Color(nsColor: .textBackgroundColor)
        static let bottomPanelBackground = Color(nsColor: .controlBackgroundColor)
        static let detailPanelBackground = Color(nsColor: .windowBackgroundColor)

        // Status
        static let running = Color.green
        static let pending = Color.yellow
        static let failed = Color.red
        static let succeeded = Color.blue
        static let terminated = Color.gray
        static let unknown = Color.orange
        static let warning = Color.orange

        // Semantic backgrounds
        static let errorBackground = Color.red.opacity(0.08)
        static let warningBackground = Color.orange.opacity(0.08)
        static let successBackground = Color.green.opacity(0.08)
        static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.4)

        // UI
        static let accent = Color.accentColor
        static let separator = Color(nsColor: .separatorColor)
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

        static func forStatus(_ status: String) -> Color {
            switch status.lowercased() {
            case "running", "active", "bound", "ready", "available":
                return running
            case "pending", "containercreating", "waiting":
                return pending
            case "failed", "error", "crashloopbackoff", "imagepullbackoff", "evicted":
                return failed
            case "succeeded", "completed":
                return succeeded
            case "terminated", "terminating":
                return terminated
            case "warning":
                return warning
            default:
                return unknown
            }
        }
    }

    // MARK: - Fonts

    enum Fonts {
        static let monoSmall = Font.system(size: 11, design: .monospaced)
        static let monoMedium = Font.system(size: 12, design: .monospaced)
        static let monoLarge = Font.system(size: 13, design: .monospaced)
        static let sidebarItem = Font.system(size: 12)
        static let sidebarHeader = Font.system(size: 11, weight: .semibold)
        static let tableHeader = Font.system(size: 11, weight: .medium)
        static let tableCell = Font.system(size: 12)
        static let title = Font.system(size: 16, weight: .semibold)
        static let subtitle = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 10)
        static let errorMessage = Font.system(size: 12, weight: .medium)
    }

    // MARK: - Animations

    enum Animations {
        static let panelTransition = Animation.easeInOut(duration: 0.2)
        static let contentTransition = Animation.easeOut(duration: 0.15)
    }

    // MARK: - Dimensions

    enum Dimensions {
        static let hotbarWidth: CGFloat = 48
        static let sidebarWidth: CGFloat = 220
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 320
        static let detailPanelWidth: CGFloat = 380
        static let bottomPanelMinHeight: CGFloat = 100
        static let bottomPanelMaxHeight: CGFloat = 600
        static let bottomPanelDefaultHeight: CGFloat = 250
        static let tableRowHeight: CGFloat = 28
        static let iconSize: CGFloat = 16
        static let statusBadgeHeight: CGFloat = 20
        static let cornerRadius: CGFloat = 6
        static let spacing: CGFloat = 8
        static let smallSpacing: CGFloat = 4
        static let padding: CGFloat = 12
    }
}
