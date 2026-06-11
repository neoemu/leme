import SwiftUI

// MARK: - Line diff

/// Minimal git-style line diff used to review YAML edits before applying.
enum YAMLDiff {
    enum Kind: Sendable {
        case context
        case added
        case removed
        /// Collapsed run of unchanged lines ("⋯ N unchanged lines").
        case gap(count: Int)
    }

    struct Line: Identifiable, Sendable {
        let id: Int
        let kind: Kind
        let text: String
    }

    /// Returns the diff collapsed to hunks with `context` unchanged lines
    /// around each change.
    static func hunks(original: String, edited: String, context: Int = 3) -> [Line] {
        let full = diff(original: original, edited: edited)
        guard full.contains(where: { if case .context = $0.kind { return false } else { return true } }) else {
            return []
        }

        var result: [Line] = []
        var index = 0
        var nextID = 0

        while index < full.count {
            if case .context = full[index].kind {
                var runEnd = index
                while runEnd < full.count, case .context = full[runEnd].kind {
                    runEnd += 1
                }
                let runLength = runEnd - index
                let keepLeading = index == 0 ? 0 : context
                let keepTrailing = runEnd == full.count ? 0 : context

                if runLength <= keepLeading + keepTrailing + 1 {
                    for line in full[index..<runEnd] {
                        result.append(Line(id: nextID, kind: .context, text: line.text))
                        nextID += 1
                    }
                } else {
                    for line in full[index..<(index + keepLeading)] {
                        result.append(Line(id: nextID, kind: .context, text: line.text))
                        nextID += 1
                    }
                    result.append(Line(id: nextID, kind: .gap(count: runLength - keepLeading - keepTrailing), text: ""))
                    nextID += 1
                    for line in full[(runEnd - keepTrailing)..<runEnd] {
                        result.append(Line(id: nextID, kind: .context, text: line.text))
                        nextID += 1
                    }
                }
                index = runEnd
            } else {
                result.append(Line(id: nextID, kind: full[index].kind, text: full[index].text))
                nextID += 1
                index += 1
            }
        }

        return result
    }

    static func changeCounts(_ lines: [Line]) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in lines {
            switch line.kind {
            case .added: added += 1
            case .removed: removed += 1
            default: break
            }
        }
        return (added, removed)
    }

    /// Full line diff (context + added + removed), via LCS over the middle
    /// section after trimming the common prefix/suffix.
    static func diff(original: String, edited: String) -> [Line] {
        let oldLines = original.components(separatedBy: "\n")
        let newLines = edited.components(separatedBy: "\n")

        // Trim common prefix/suffix: typical YAML edits touch a few lines,
        // which keeps the LCS table tiny.
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix,
              suffix < newLines.count - prefix,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        let oldMiddle = Array(oldLines[prefix..<(oldLines.count - suffix)])
        let newMiddle = Array(newLines[prefix..<(newLines.count - suffix)])

        var lines: [Line] = []
        var nextID = 0
        func append(_ kind: Kind, _ text: String) {
            lines.append(Line(id: nextID, kind: kind, text: text))
            nextID += 1
        }

        for line in oldLines[0..<prefix] {
            append(.context, line)
        }

        // Guard against pathological sizes (full-file rewrites of huge YAML).
        if oldMiddle.count * newMiddle.count > 4_000_000 {
            for line in oldMiddle { append(.removed, line) }
            for line in newMiddle { append(.added, line) }
        } else {
            for entry in lcsDiff(oldMiddle, newMiddle) {
                append(entry.0, entry.1)
            }
        }

        for line in oldLines[(oldLines.count - suffix)...] {
            append(.context, line)
        }

        return lines
    }

    private static func lcsDiff(_ old: [String], _ new: [String]) -> [(Kind, String)] {
        let n = old.count
        let m = new.count
        guard n > 0 || m > 0 else { return [] }

        var table = [Int](repeating: 0, count: (n + 1) * (m + 1))
        func idx(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }

        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if old[i] == new[j] {
                    table[idx(i, j)] = table[idx(i + 1, j + 1)] + 1
                } else {
                    table[idx(i, j)] = max(table[idx(i + 1, j)], table[idx(i, j + 1)])
                }
            }
        }

        var result: [(Kind, String)] = []
        var i = 0
        var j = 0
        while i < n, j < m {
            if old[i] == new[j] {
                result.append((.context, old[i]))
                i += 1
                j += 1
            } else if table[idx(i + 1, j)] >= table[idx(i, j + 1)] {
                result.append((.removed, old[i]))
                i += 1
            } else {
                result.append((.added, new[j]))
                j += 1
            }
        }
        while i < n {
            result.append((.removed, old[i]))
            i += 1
        }
        while j < m {
            result.append((.added, new[j]))
            j += 1
        }
        return result
    }
}

// MARK: - Review sheet

/// Git-style review of pending YAML changes before applying them to the
/// cluster. On production clusters the confirm button is gated behind
/// typing the cluster name.
struct YAMLDiffReviewSheet: View {
    let title: String
    let lines: [YAMLDiff.Line]
    let isProduction: Bool
    let clusterName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var typedText = ""
    @FocusState private var isFieldFocused: Bool

    private var isConfirmed: Bool {
        !isProduction || typedText == clusterName
    }

    private var counts: (added: Int, removed: Int) {
        YAMLDiff.changeCounts(lines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            diffContent
            Divider()
            footer
        }
        .frame(width: 700, height: 500)
    }

    private var header: some View {
        HStack(spacing: Theme.Dimensions.spacing) {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)

            Text("Review Changes")
                .font(Theme.Fonts.title)

            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("+\(counts.added)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.running)
            Text("−\(counts.removed)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.failed)
        }
        .padding(Theme.Dimensions.padding)
    }

    private var diffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    diffRow(line)
                }
            }
            .padding(.vertical, Theme.Dimensions.smallSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func diffRow(_ line: YAMLDiff.Line) -> some View {
        switch line.kind {
        case .gap(let count):
            Text("⋯ \(count) unchanged line\(count == 1 ? "" : "s")")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 3)
        case .context, .added, .removed:
            HStack(spacing: 6) {
                Text(marker(for: line.kind))
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(color(for: line.kind))
                    .frame(width: 10, alignment: .center)
                Text(line.text.isEmpty ? " " : line.text)
                    .font(Theme.Fonts.monoSmall)
                    .foregroundStyle(foregroundColor(for: line.kind))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, 1)
            .background(background(for: line.kind))
            .textSelection(.enabled)
        }
    }

    private func marker(for kind: YAMLDiff.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        default: return " "
        }
    }

    private func color(for kind: YAMLDiff.Kind) -> Color {
        switch kind {
        case .added: return Theme.Colors.running
        case .removed: return Theme.Colors.failed
        default: return Theme.Colors.tertiaryText
        }
    }

    private func foregroundColor(for kind: YAMLDiff.Kind) -> Color {
        switch kind {
        case .context: return Theme.Colors.secondaryText
        default: return .primary
        }
    }

    private func background(for kind: YAMLDiff.Kind) -> Color {
        switch kind {
        case .added: return Theme.Colors.running.opacity(0.10)
        case .removed: return Theme.Colors.failed.opacity(0.10)
        default: return .clear
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.spacing) {
            if isProduction {
                HStack(spacing: Theme.Dimensions.smallSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.failed)
                    Text("PRODUCTION CLUSTER")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.Colors.failed)

                    (Text("Type ") + Text(clusterName).bold().font(Theme.Fonts.monoSmall) + Text(" to confirm:"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    TextField(clusterName, text: $typedText)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Fonts.monoSmall)
                        .focused($isFieldFocused)
                        .frame(maxWidth: 220)
                }
                .padding(Theme.Dimensions.smallSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                        .fill(Theme.Colors.errorBackground)
                )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply Changes", role: isProduction ? .destructive : nil, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConfirmed)
            }
        }
        .padding(Theme.Dimensions.padding)
        .onAppear {
            if isProduction {
                isFieldFocused = true
            }
        }
    }
}
