import SwiftUI

struct LabelBadgeList: View {
    let labels: [String: String]
    var maxVisible: Int = 5
    @State private var showAll = false

    private var sortedLabels: [(String, String)] {
        labels.sorted { $0.key < $1.key }
    }

    private var visibleLabels: [(String, String)] {
        if showAll {
            return sortedLabels
        }
        return Array(sortedLabels.prefix(maxVisible))
    }

    private var hasMore: Bool {
        sortedLabels.count > maxVisible
    }

    var body: some View {
        if labels.isEmpty {
            Text("-")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(visibleLabels, id: \.0) { key, value in
                    labelBadge(key: key, value: value)
                }

                if hasMore {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAll.toggle()
                        }
                    } label: {
                        Text(showAll ? "Show less" : "Show more")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func labelBadge(key: String, value: String) -> some View {
        Text("\(key)=\(value)")
            .font(Theme.Fonts.monoSmall)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Color.secondary.opacity(0.1))
            )
            .foregroundStyle(Theme.Colors.secondaryText)
    }
}

// MARK: - FlowLayout for wrapping badges

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + rowHeight),
            positions: positions
        )
    }
}
