import SwiftUI

struct CapacityBar: View {
    let label: String
    let used: Double
    let total: Double
    let unit: String
    var compact: Bool = false

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(used / total, 1.0)
    }

    private var percentage: String {
        String(format: "%.2f%%", fraction * 100)
    }

    private var barColor: Color {
        switch fraction {
        case 0..<0.70:
            return Theme.Colors.capacityLow
        case 0.70..<0.85:
            return Theme.Colors.capacityMedium
        default:
            return Theme.Colors.capacityHigh
        }
    }

    private var usedText: String {
        if used == used.rounded() && used < 10000 {
            return String(format: "%.0f", used)
        }
        return String(format: "%.2f", used)
    }

    private var totalText: String {
        if total == total.rounded() && total < 10000 {
            return String(format: "%.0f", total)
        }
        return String(format: "%.1f", total)
    }

    var body: some View {
        if compact {
            compactBar
        } else {
            fullBar
        }
    }

    // MARK: - Compact Mode (for node table cells)

    private var compactBar: some View {
        HStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.capacityBackground)
                        .frame(height: Theme.Dimensions.miniBarHeight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(
                            width: max(0, geometry.size.width * fraction),
                            height: Theme.Dimensions.miniBarHeight
                        )
                }
                .frame(height: Theme.Dimensions.miniBarHeight)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: Theme.Dimensions.miniBarWidth)

            Text(percentage)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Full Mode (for dashboard)

    private var fullBar: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
            HStack {
                Text(label)
                    .font(Theme.Fonts.subtitle)
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack {
                Text("\(usedText) / \(totalText) \(unit)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                Text(percentage)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Colors.capacityBackground)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, geometry.size.width * fraction))
                }
            }
            .frame(height: Theme.Dimensions.capacityBarHeight)
        }
    }
}
