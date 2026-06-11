import AppKit
import SwiftUI
import SwiftTerm

struct TerminalContainerView: NSViewRepresentable {
    @AppStorage("kubeconfigPath") private var kubeconfigPath = Constants.defaultKubeconfigPath
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
        let environment = buildProcessEnvironment()

        // Start the appropriate process based on session type
        switch session.type {
        case .local:
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
            if let container, !container.isEmpty {
                args.append(contentsOf: ["-c", container])
            }
            args.append(contentsOf: ["--", "/bin/sh"])

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
        return "kubectl"
    }

    private func buildProcessEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment

        // Merge SwiftTerm defaults (TERM, etc.) while keeping host environment values.
        for entry in Terminal.getEnvironmentVariables(termName: "xterm-256color") {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            if env[key] == nil {
                env[key] = value
            }
        }

        if env["HOME"]?.isEmpty != false {
            env["HOME"] = NSHomeDirectory()
        }

        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = enrichedPath(from: currentPath)

        let expandedKubeconfigPath = (kubeconfigPath as NSString).expandingTildeInPath
        if env["KUBECONFIG"]?.isEmpty != false,
           !expandedKubeconfigPath.isEmpty,
           FileManager.default.fileExists(atPath: expandedKubeconfigPath) {
            env["KUBECONFIG"] = expandedKubeconfigPath
        }

        return env.map { "\($0.key)=\($0.value)" }
    }

    private func enrichedPath(from currentPath: String) -> String {
        let requiredPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPaths = currentPath
            .split(separator: ":")
            .map(String.init)
        let existingSet = Set(existingPaths)
        let missingPaths = requiredPaths.filter { !existingSet.contains($0) }
        return (missingPaths + existingPaths).joined(separator: ":")
    }
}
