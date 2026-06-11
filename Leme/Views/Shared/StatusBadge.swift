import SwiftUI

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.forStatus(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Theme.Colors.forStatus(status).opacity(0.15))
            )
            .frame(height: Theme.Dimensions.statusBadgeHeight)
    }
}
