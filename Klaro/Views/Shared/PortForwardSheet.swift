import SwiftUI

/// Sheet collecting local/remote ports before starting a kubectl port-forward.
struct PortForwardSheet: View {
    let targetKind: String
    let targetName: String
    let namespace: String
    /// Ports declared by the target (containerPorts / service ports), used to
    /// pre-fill the form so the user doesn't have to look them up.
    var suggestedPorts: [Int] = []
    let onStart: (_ localPort: Int, _ remotePort: Int) -> Void
    let onCancel: () -> Void

    @State private var localPortText = "8080"
    @State private var remotePortText = "80"

    private var localPort: Int? { Int(localPortText) }
    private var remotePort: Int? { Int(remotePortText) }

    private var isValid: Bool {
        guard let localPort, let remotePort else { return false }
        return (1...65535).contains(localPort) && (1...65535).contains(remotePort)
    }

    /// Privileged ports need root to bind locally; offset them (80 → 8080).
    private static func suggestedLocalPort(forRemote remote: Int) -> Int {
        remote < 1024 ? remote + 8000 : remote
    }

    private func applySuggestion(_ port: Int) {
        remotePortText = "\(port)"
        localPortText = "\(Self.suggestedLocalPort(forRemote: port))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Dimensions.sectionSpacing) {
            Text("Port Forward")
                .font(Theme.Fonts.title)

            Text("\(targetKind)/\(targetName) in \(namespace)")
                .font(Theme.Fonts.monoSmall)
                .foregroundStyle(Theme.Colors.secondaryText)

            if suggestedPorts.count > 1 {
                HStack(spacing: Theme.Dimensions.smallSpacing) {
                    Text("Ports:")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    ForEach(suggestedPorts, id: \.self) { port in
                        Button("\(port)") {
                            applySuggestion(port)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(remotePort == port ? Theme.Colors.accent : nil)
                    }
                }
            }

            HStack(spacing: Theme.Dimensions.spacing) {
                VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
                    Text("Local port")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    TextField("8080", text: $localPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: Theme.Dimensions.smallSpacing) {
                    Text("Remote port")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    TextField("80", text: $remotePortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    if let localPort, let remotePort {
                        onStart(localPort, remotePort)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Theme.Dimensions.sectionSpacing)
        .frame(width: 340)
        .onAppear {
            if let first = suggestedPorts.first {
                applySuggestion(first)
            }
        }
    }
}

/// Toolbar popover listing active port-forward sessions.
struct PortForwardListPopover: View {
    @Environment(PortForwardManager.self) private var portForwardManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if portForwardManager.sessions.isEmpty {
                Text("No active port forwards")
                    .font(Theme.Fonts.sidebarItem)
                    .foregroundStyle(.secondary)
                    .padding(Theme.Dimensions.padding)
            } else {
                ForEach(portForwardManager.sessions) { session in
                    HStack(spacing: Theme.Dimensions.spacing) {
                        Circle()
                            .fill(statusColor(session.status))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.displayName)
                                .font(Theme.Fonts.monoSmall)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if case .failed(let reason) = session.status {
                                Text(reason)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.failed)
                                    .lineLimit(2)
                            } else {
                                Text("\(session.namespace) · localhost:\(session.localPort)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: Theme.Dimensions.smallSpacing)

                        if session.status == .active, let url = session.localURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "safari")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Open localhost:\(session.localPort) in browser")
                        }

                        Button {
                            portForwardManager.stop(id: session.id)
                        } label: {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Colors.failed)
                        }
                        .buttonStyle(.plain)
                        .help("Stop forward")
                    }
                    .padding(.horizontal, Theme.Dimensions.padding)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, Theme.Dimensions.smallSpacing)
        .frame(width: 320)
    }

    private func statusColor(_ status: PortForwardStatus) -> Color {
        switch status {
        case .starting: return Theme.Colors.pending
        case .active: return Theme.Colors.running
        case .failed: return Theme.Colors.failed
        }
    }
}
