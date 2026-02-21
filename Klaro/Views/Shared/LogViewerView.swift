import SwiftUI

struct LogViewerView: View {
    @Bindable var viewModel: PodLogsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logContent
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            // Search
            HStack(spacing: Theme.Dimensions.smallSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.secondaryText)

                TextField("Filter logs...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.monoSmall)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(Color.primary.opacity(0.05))
            )
            .frame(maxWidth: 250)

            // Container picker
            if viewModel.availableContainers.count > 1 {
                Picker("Container", selection: $viewModel.selectedContainer) {
                    ForEach(viewModel.availableContainers, id: \.self) { container in
                        Text(container).tag(Optional(container))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            Spacer()

            // Line count
            Text("\(viewModel.filteredLogLines.count) lines")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            Divider()
                .frame(height: 14)

            // Toggle buttons
            toolbarButton(
                icon: "arrow.down.to.line",
                label: "Follow",
                isActive: viewModel.isFollowing
            ) {
                viewModel.isFollowing.toggle()
            }

            toolbarButton(
                icon: "clock",
                label: "Timestamps",
                isActive: viewModel.showTimestamps
            ) {
                viewModel.showTimestamps.toggle()
            }

            toolbarButton(
                icon: "trash",
                label: "Clear",
                isActive: false
            ) {
                viewModel.clearLogs()
            }

            // Streaming indicator
            if viewModel.isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.Colors.running)
                        .frame(width: 6, height: 6)
                    Text("Streaming")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, Theme.Dimensions.padding)
        .padding(.vertical, 6)
    }

    private func toolbarButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Theme.Fonts.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                    .fill(isActive ? Theme.Colors.accent.opacity(0.15) : .clear)
            )
            .foregroundStyle(isActive ? Theme.Colors.accent : Theme.Colors.secondaryText)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Content

    @ViewBuilder
    private var logContent: some View {
        if let error = viewModel.errorMessage {
            VStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.failed)
                Text(error)
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.logLines.isEmpty && !viewModel.isStreaming {
            VStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.tertiaryText)
                Text("No log output yet")
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            logScrollView
        }
    }

    private var logScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let lines = viewModel.filteredLogLines
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        logLineView(line, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.smallSpacing)
            }
            .onChange(of: viewModel.logLines.count) { _, _ in
                if viewModel.isFollowing {
                    let targetIndex = viewModel.filteredLogLines.count - 1
                    if targetIndex >= 0 {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(targetIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func logLineView(_ line: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Dimensions.spacing) {
            // Line number
            Text("\(index + 1)")
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .frame(width: 40, alignment: .trailing)

            // Log text
            Text(line)
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}
