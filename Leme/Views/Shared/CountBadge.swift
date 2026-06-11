import SwiftUI

struct CountBadge: View {
    let count: Int
    let errorCount: Int?
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Dimensions.spacing) {
            HStack(alignment: .top, spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()

                Text(title)
                    .font(Theme.Fonts.subtitle)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                if let errorCount, errorCount > 0 {
                    Text("\(errorCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.failed)
                        )
                }
            }
        }
        .padding(Theme.Dimensions.padding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cardCornerRadius)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
}
