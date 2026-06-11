import AppKit
import SwiftUI
import CodeEditor

struct YAMLEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settingsStore

    @Binding var source: String
    var title: String = "YAML Editor"
    /// When set, Apply opens a git-style review of the pending changes first.
    var originalSource: String?
    var onClose: (() -> Void)?
    var onApply: ((String) async throws -> String)?

    @State private var searchText: String = ""
    @State private var searchMatches: [Range<Int>] = []
    @State private var currentMatchIndex: Int = 0
    @State private var selectedOffsets: Range<Int> = 0..<0
    @State private var isApplying = false
    @State private var applyStatusMessage: String?
    @State private var applyStatusIsError = false
    @State private var pendingDiffLines: [YAMLDiff.Line]?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(Theme.Fonts.subtitle)
                    .foregroundStyle(.secondary)
                if let applyStatusMessage {
                    Text(applyStatusMessage)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(applyStatusIsError ? Theme.Colors.failed : Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                if let onApply {
                    Button {
                        requestApply(onApply)
                    } label: {
                        HStack(spacing: Theme.Dimensions.smallSpacing) {
                            Image(systemName: isApplying ? "hourglass" : "checkmark.circle")
                                .font(.system(size: 11))
                            Text(isApplying ? "Applying..." : "Apply")
                                .font(Theme.Fonts.sidebarItem)
                        }
                        .padding(.horizontal, Theme.Dimensions.spacing)
                        .padding(.vertical, Theme.Dimensions.smallSpacing)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                                .fill(Theme.Colors.accent.opacity(0.15))
                        )
                        .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.spacing)

            Divider()

            // Search bar
            HStack(spacing: Theme.Dimensions.spacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.secondaryText)

                TextField("Search in YAML...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.sidebarItem)
                    .onSubmit {
                        moveToNextMatch()
                    }

                if !searchText.isEmpty {
                    Text(searchStatusText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(minWidth: 52, alignment: .trailing)
                }

                Button {
                    moveToPreviousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(searchMatches.isEmpty)

                Button {
                    moveToNextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(searchMatches.isEmpty)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.smallSpacing)

            Divider()

            // Code editor
            CodeEditor(
                source: $source,
                selection: editorSelectionBinding,
                language: .yaml,
                theme: .ocean,
                flags: .defaultEditorFlags,
                indentStyle: .softTab(width: 2)
            )
            .onAppear {
                refreshSearchMatches(resetIndex: true)
            }
            .onChange(of: searchText) { _, _ in
                refreshSearchMatches(resetIndex: true)
            }
            .onChange(of: source) { _, _ in
                refreshSearchMatches(resetIndex: false, updateSelection: false)
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingDiffLines != nil },
            set: { if !$0 { pendingDiffLines = nil } }
        )) {
            if let lines = pendingDiffLines, let onApply {
                YAMLDiffReviewSheet(
                    title: title,
                    lines: lines,
                    isProduction: settingsStore.isProduction(appState.activeCluster),
                    clusterName: appState.activeCluster?.displayName ?? "",
                    onConfirm: {
                        pendingDiffLines = nil
                        Task { await runApply(onApply) }
                    },
                    onCancel: {
                        pendingDiffLines = nil
                    }
                )
            }
        }
    }

    /// Shows the change review when there is an original to diff against;
    /// otherwise applies directly (e.g. fresh manifests with no baseline).
    private func requestApply(_ onApply: @escaping (String) async throws -> String) {
        guard let originalSource else {
            Task { await runApply(onApply) }
            return
        }

        let lines = YAMLDiff.hunks(original: originalSource, edited: source)
        guard !lines.isEmpty else {
            applyStatusIsError = false
            applyStatusMessage = "No changes to apply."
            return
        }
        pendingDiffLines = lines
    }

    private var editorSelectionBinding: Binding<Range<String.Index>> {
        Binding(
            get: {
                offsetRangeToStringRange(selectedOffsets, in: source)
            },
            set: { newSelection in
                selectedOffsets = stringRangeToOffsetRange(newSelection, in: source)
            }
        )
    }

    private var searchStatusText: String {
        guard !searchMatches.isEmpty else { return "0 results" }
        return "\(currentMatchIndex + 1)/\(searchMatches.count)"
    }

    private func refreshSearchMatches(resetIndex: Bool, updateSelection: Bool = true) {
        searchMatches = Self.findMatches(in: source, query: searchText)

        guard !searchMatches.isEmpty else {
            currentMatchIndex = 0
            if updateSelection {
                selectedOffsets = 0..<0
            }
            return
        }

        if resetIndex || currentMatchIndex >= searchMatches.count {
            currentMatchIndex = 0
        }

        if updateSelection {
            selectedOffsets = searchMatches[currentMatchIndex]
        }
    }

    private func moveToNextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        selectedOffsets = searchMatches[currentMatchIndex]
    }

    private func moveToPreviousMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        selectedOffsets = searchMatches[currentMatchIndex]
    }

    private func runApply(_ onApply: @escaping (String) async throws -> String) async {
        isApplying = true
        defer { isApplying = false }

        do {
            let status = try await onApply(source)
            applyStatusIsError = false
            applyStatusMessage = status
        } catch {
            applyStatusIsError = true
            applyStatusMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private static func findMatches(in text: String, query: String) -> [Range<Int>] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var matches: [Range<Int>] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            guard let range = text.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
            ) else { break }

            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            matches.append(lower..<upper)

            if range.upperBound == searchStart {
                searchStart = text.index(after: searchStart)
            } else {
                searchStart = range.upperBound
            }
        }

        return matches
    }

    private func offsetRangeToStringRange(_ offsets: Range<Int>, in text: String) -> Range<String.Index> {
        let lowerOffset = min(max(offsets.lowerBound, 0), text.count)
        let upperOffset = min(max(offsets.upperBound, lowerOffset), text.count)
        let lower = text.index(text.startIndex, offsetBy: lowerOffset)
        let upper = text.index(text.startIndex, offsetBy: upperOffset)
        return lower..<upper
    }

    private func stringRangeToOffsetRange(_ range: Range<String.Index>, in text: String) -> Range<Int> {
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return lower..<upper
    }
}
