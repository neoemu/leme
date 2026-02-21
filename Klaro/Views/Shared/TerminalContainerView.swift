import AppKit
import SwiftUI
import SwiftTerm

struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession
    let kubeContext: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = LocalProcessTerminalView(frame: .zero)

        // Configure appearance: dark background, light foreground, monospace font
        let fontSize: CGFloat = 13
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.font = monoFont
        tv.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        tv.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)

        // Start the appropriate process based on session type
        switch session.type {
        case .local:
            var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            if let ctx = kubeContext {
                // Add KUBECONFIG hint if context is provided
                environment.append("KUBECONFIG=\(ctx)")
            }
            tv.startProcess(
                executable: "/bin/zsh",
                args: ["-l"],
                environment: environment,
                execName: "zsh"
            )

        case .podExec(let podName, let namespace, let container):
            let kubectlPath = findKubectl()
            var args = ["exec", "-it", podName, "-n", namespace]
            if let ctx = kubeContext {
                args.append(contentsOf: ["--context", ctx])
            }
            args.append(contentsOf: ["-c", container, "--", "/bin/sh"])

            let environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            tv.startProcess(
                executable: kubectlPath,
                args: args,
                environment: environment,
                execName: "kubectl"
            )
        }

        return tv
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // No dynamic updates needed; process is started in makeNSView
    }

    // MARK: - kubectl Path Resolution

    private func findKubectl() -> String {
        let commonPaths = [
            "/usr/local/bin/kubectl",
            "/opt/homebrew/bin/kubectl",
            "/usr/bin/kubectl",
            "/opt/local/bin/kubectl",
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: assume it is on PATH and let the process fail with a clear error
        return "/usr/local/bin/kubectl"
    }
}
