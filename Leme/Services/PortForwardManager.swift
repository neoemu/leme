import Foundation

enum PortForwardStatus: Equatable, Sendable {
    case starting
    case active
    case failed(String)

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .active: return "Active"
        case .failed: return "Failed"
        }
    }
}

/// Manages `kubectl port-forward` child processes. Sessions stay alive until
/// stopped here, the process dies, or the app terminates (stopAll on quit).
@Observable
@MainActor
final class PortForwardManager {

    struct Session: Identifiable {
        let id: UUID
        /// kubectl target, e.g. "pod/my-pod" or "service/my-svc"
        let target: String
        let namespace: String
        let contextName: String?
        let localPort: Int
        let remotePort: Int
        var status: PortForwardStatus
        let process: Process

        var displayName: String {
            "\(target) \(localPort)→\(remotePort)"
        }

        var localURL: URL? {
            URL(string: "http://localhost:\(localPort)")
        }
    }

    private(set) var sessions: [Session] = []

    var activeCount: Int {
        sessions.count
    }

    func start(
        target: String,
        namespace: String,
        localPort: Int,
        remotePort: Int,
        contextName: String?
    ) {
        guard let kubectlPath = Self.findKubectl() else {
            sessions.append(Session(
                id: UUID(),
                target: target,
                namespace: namespace,
                contextName: contextName,
                localPort: localPort,
                remotePort: remotePort,
                status: .failed("kubectl not found in PATH"),
                process: Process()
            ))
            return
        }

        var arguments = ["port-forward", target, "\(localPort):\(remotePort)", "-n", namespace]
        if let contextName, !contextName.isEmpty {
            arguments.append(contentsOf: ["--context", contextName])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        } else {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let sessionID = UUID()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard text.contains("Forwarding from") else { return }
            Task { @MainActor [weak self] in
                self?.updateStatus(id: sessionID, status: .active)
            }
        }

        nonisolated(unsafe) var stderrBuffer = ""
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            stderrBuffer += text
        }

        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            let detail = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                guard let self, let index = self.sessions.firstIndex(where: { $0.id == sessionID }) else {
                    return
                }
                if status == 0 || status == 15 {
                    // Clean exit (usually our own terminate) — drop the session.
                    self.sessions.remove(at: index)
                } else {
                    self.sessions[index].status = .failed(detail.isEmpty ? "exited with code \(status)" : detail)
                }
            }
        }

        do {
            try process.run()
        } catch {
            sessions.append(Session(
                id: sessionID,
                target: target,
                namespace: namespace,
                contextName: contextName,
                localPort: localPort,
                remotePort: remotePort,
                status: .failed(error.localizedDescription),
                process: process
            ))
            return
        }

        sessions.append(Session(
            id: sessionID,
            target: target,
            namespace: namespace,
            contextName: contextName,
            localPort: localPort,
            remotePort: remotePort,
            status: .starting,
            process: process
        ))
    }

    func stop(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: index)
        if session.process.isRunning {
            session.process.terminate()
        }
    }

    func stopAll() {
        let stopping = sessions
        sessions.removeAll()
        for session in stopping where session.process.isRunning {
            session.process.terminate()
        }
    }

    private func updateStatus(id: UUID, status: PortForwardStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].status = status
    }

    private nonisolated static func findKubectl() -> String? {
        let commonPaths = [
            "/usr/local/bin/kubectl",
            "/opt/homebrew/bin/kubectl",
            "/usr/bin/kubectl",
            "/opt/local/bin/kubectl",
        ]
        return commonPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
