import SwiftUI

struct AgeLabel: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(date.relativeAge)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}
