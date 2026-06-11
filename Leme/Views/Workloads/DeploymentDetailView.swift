import SwiftUI

struct DeploymentDetailView: View {
    @Bindable var viewModel: ResourceDetailViewModel

    var body: some View {
        ResourceDetailPanel(viewModel: viewModel)
    }
}
