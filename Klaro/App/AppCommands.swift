import SwiftUI

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Command Palette") {
                appState.isCommandPaletteOpen.toggle()
            }
            .keyboardShortcut(KeyboardShortcuts.commandPalette, modifiers: [.command, .shift])

            Divider()

            ForEach(ResourceCategory.allCases) { category in
                Menu(category.rawValue) {
                    ForEach(category.resourceKinds) { kind in
                        Button(kind.pluralName) {
                            appState.selectedResourceKind = kind
                        }
                    }
                }
            }
        }

        CommandMenu("Cluster") {
            Button("Toggle Logs Panel") {
                if appState.isBottomPanelOpen && appState.bottomPanelMode == .logs {
                    appState.isBottomPanelOpen = false
                } else {
                    appState.openBottomPanel(mode: .logs)
                }
            }
            .keyboardShortcut(KeyboardShortcuts.logs, modifiers: [.command, .shift])

            Button("Toggle Terminal") {
                if appState.isBottomPanelOpen && appState.bottomPanelMode == .terminal {
                    appState.isBottomPanelOpen = false
                } else {
                    appState.openBottomPanel(mode: .terminal)
                }
            }
            .keyboardShortcut(KeyboardShortcuts.terminal, modifiers: [.command, .shift])

            Divider()

            Button("Toggle Detail Panel") {
                if appState.isYAMLEditorOpen {
                    appState.closeYAMLEditor()
                } else {
                    appState.isDetailPanelOpen.toggle()
                }
            }
            .keyboardShortcut(KeyboardShortcuts.detailPanel, modifiers: [.command, .shift])

            Button("Close Bottom Panel") {
                appState.isBottomPanelOpen = false
            }
            .keyboardShortcut(KeyboardShortcuts.closeBottomPanel, modifiers: [.command, .shift])
        }
    }
}
