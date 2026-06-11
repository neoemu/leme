import SwiftUI

extension Color {
    static func statusColor(_ status: String) -> Color {
        Theme.Colors.forStatus(status)
    }
}
