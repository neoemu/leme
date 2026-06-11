import Foundation
import AppKit
import SwiftUI

struct LogViewerView: View {
    @Bindable var viewModel: PodLogsViewModel
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logContent
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
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

            Button {
                copyVisibleLogsToClipboard()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopyFeedbackVisible ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(isCopyFeedbackVisible ? "Copied" : "Copy")
                        .font(Theme.Fonts.caption)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .fill(isCopyFeedbackVisible ? Theme.Colors.successBackground : .clear)
                )
                .foregroundStyle(isCopyFeedbackVisible ? Theme.Colors.running : Theme.Colors.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Copy visible logs")

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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: Theme.Dimensions.spacing) {
                        Text(lineNumberText)
                            .font(Theme.Fonts.monoSmall)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .frame(width: 44, alignment: .trailing)
                            .textSelection(.disabled)

                        Text(rawLogText)
                            .font(Theme.Fonts.monoSmall)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("log-bottom-anchor")
                }
                .padding(.horizontal, Theme.Dimensions.padding)
                .padding(.vertical, Theme.Dimensions.smallSpacing)
            }
            .onChange(of: viewModel.logLines.count) { _, _ in
                if viewModel.isFollowing {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("log-bottom-anchor", anchor: .bottom)
                    }
                }
            }
            .contextMenu {
                Button("Copy Logs") {
                    copyVisibleLogsToClipboard()
                }
            }
        }
    }

    private var lineNumberText: String {
        viewModel.filteredLogLines
            .enumerated()
            .map { index, _ in
                let lineNumber = String(format: "%5d", index + 1)
                return lineNumber
            }
            .joined(separator: "\n")
    }

    private var rawLogText: String {
        viewModel.filteredLogLines.joined(separator: "\n")
    }

    private func copyVisibleLogsToClipboard() {
        guard !rawLogText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawLogText, forType: .string)
        showCopyFeedback()
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            isCopyFeedbackVisible = true
        }

        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    isCopyFeedbackVisible = false
                }
            }
        }
    }
}
