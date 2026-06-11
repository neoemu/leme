import SwiftUI

struct InfoPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Dimensions.smallSpacing) {
            Text("\(label):")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(value)
                .font(Theme.Fonts.subtitle)
                .foregroundStyle(.primary)
        }
    }
}
