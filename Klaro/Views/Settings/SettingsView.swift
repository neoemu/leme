import SwiftUI

struct SettingsView: View {
    @AppStorage("kubeconfigPath") private var kubeconfigPath = "~/.kube/config"
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 30.0
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalShellPath") private var terminalShellPath = "/bin/zsh"

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
            terminalSettings
                .tabItem { Label("Terminal", systemImage: "terminal") }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Kubeconfig") {
                LabeledContent("Path") {
                    Text(kubeconfigPath)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Auto-Refresh") {
                Picker("Interval", selection: $autoRefreshInterval) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("Disabled").tag(0.0)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Terminal

    private var terminalSettings: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $terminalFontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Stepper("", value: $terminalFontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }
            }

            Section("Shell") {
                TextField("Shell Path", text: $terminalShellPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
