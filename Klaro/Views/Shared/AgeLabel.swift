import SwiftUI

struct AgeLabel: View {
    let date: Date

    var body: some View {
        Text(date.relativeAge)
            .font(Theme.Fonts.monoSmall)
            .foregroundStyle(Theme.Colors.secondaryText)
    }
}
