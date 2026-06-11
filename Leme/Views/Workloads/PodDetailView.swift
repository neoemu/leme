import SwiftUI

struct PodDetailView: View {
    @Bindable var viewModel: ResourceDetailViewModel

    var body: some View {
        ResourceDetailPanel(viewModel: viewModel)
    }
}
