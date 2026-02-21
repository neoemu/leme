import SwiftUI
import CodeEditor

struct YAMLEditorView: View {
    @Binding var source: String
    var onApply: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("YAML Editor")
                    .font(Theme.Fonts.subtitle)
                    .foregroundStyle(.secondary)
                Spacer()
                if let onApply {
                    Button {
                        onApply()
                    } label: {
                        HStack(spacing: Theme.Dimensions.smallSpacing) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                            Text("Apply")
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
                }
            }
            .padding(.horizontal, Theme.Dimensions.padding)
            .padding(.vertical, Theme.Dimensions.spacing)

            Divider()

            // Code editor
            CodeEditor(
                source: $source,
                language: .yaml,
                theme: .ocean,
                flags: .defaultEditorFlags,
                indentStyle: .softTab(width: 2)
            )
        }
    }
}
