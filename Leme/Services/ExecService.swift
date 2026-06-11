import Foundation

// MARK: - ExecServiceError

enum ExecServiceError: LocalizedError, Sendable {
    case kubectlNotFound
    case processLaunchFailed(String)
    case processTerminated(Int32)

    var errorDescription: String? {
        switch self {
        case .kubectlNotFound:
            return "kubectl not found. Ensure kubectl is installed and available in PATH."
        case .processLaunchFailed(let detail):
            return "Failed to launch exec process: \(detail)"
        case .processTerminated(let code):
            return "Exec process terminated with exit code \(code)"
        }
    }
}

// MARK: - ExecSession

/// Represents an active kubectl exec session with input/output handles
/// suitable for connecting to a SwiftTerm terminal view.
final class ExecSession: Sendable {
    /// The underlying Process. Access must be coordinated by callers.
    let process: Process
    /// File handle for writing input to the exec session (stdin of the process).
    let inputHandle: FileHandle
    /// File handle for reading output from the exec session (stdout of the process).
    let outputHandle: FileHandle
    /// File handle for reading error output from the exec session (stderr of the process).
    let errorHandle: FileHandle

    init(process: Process, inputHandle: FileHandle, outputHandle: FileHandle, errorHandle: FileHandle) {
        self.process = process
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
    }

    /// Terminates the exec session.
    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Whether the exec session process is still running.
    var isRunning: Bool {
        process.isRunning
    }
}

// MARK: - ExecService

/// Service that spawns `kubectl exec` as a Process and provides FileHandle
/// objects for input/output, suitable for connecting to a SwiftTerm terminal.
final class ExecService: @unchecked Sendable {

    // MARK: - Properties

    private var activeSessions: [UUID: ExecSession] = [:]
    private let lock = NSLock()

    // MARK: - kubectl Path Resolution

    /// Finds the path to the kubectl binary.
    private func findKubectl() throws -> String {
        // Check common paths
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

        // Try using `which`
        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["kubectl"]
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Fall through to error
        }

        throw ExecServiceError.kubectlNotFound
    }

    // MARK: - Exec Session Management

    /// Spawns a kubectl exec process and returns an ExecSession with
    /// file handles for stdin/stdout/stderr.
    ///
    /// - Parameters:
    ///   - podName: The name of the pod to exec into.
    ///   - namespace: The namespace of the pod.
    ///   - container: Optional container name within the pod.
    ///   - command: The command to execute. Defaults to ["/bin/sh"].
    ///   - kubeContext: Optional kube context to use.
    ///   - tty: Whether to allocate a pseudo-TTY. Defaults to true.
    /// - Returns: An ExecSession with process and file handles.
    func exec(
        podName: String,
        namespace: String,
        container: String? = nil,
        command: [String] = ["/bin/sh"],
        kubeContext: String? = nil,
        tty: Bool = true
    ) throws -> ExecSession {
        let kubectlPath = try findKubectl()

        var arguments = ["exec"]

        // Add interactive and TTY flags
        if tty {
            arguments.append("-it")
        } else {
            arguments.append("-i")
        }

        // Add namespace
        arguments.append(contentsOf: ["-n", namespace])

        // Add context if specified
        if let context = kubeContext {
            arguments.append(contentsOf: ["--context", context])
        }

        // Add container if specified
        if let container = container {
            arguments.append(contentsOf: ["-c", container])
        }

        // Add pod name
        arguments.append(podName)

        // Add command separator and command
        arguments.append("--")
        arguments.append(contentsOf: command)

        // Create pipes for stdin/stdout/stderr
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Configure the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set environment to inherit user's PATH for any auth helpers
        var environment = ProcessInfo.processInfo.environment
        // Ensure common binary directories are in PATH
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw ExecServiceError.processLaunchFailed(error.localizedDescription)
        }

        let session = ExecSession(
            process: process,
            inputHandle: stdinPipe.fileHandleForWriting,
            outputHandle: stdoutPipe.fileHandleForReading,
            errorHandle: stderrPipe.fileHandleForReading
        )

        let sessionID = UUID()
        lock.lock()
        activeSessions[sessionID] = session
        lock.unlock()

        // Clean up when the process terminates
        process.terminationHandler = { [weak self] _ in
            self?.lock.lock()
            self?.activeSessions.removeValue(forKey: sessionID)
            self?.lock.unlock()
        }

        return session
    }

    /// Terminates all active exec sessions.
    func terminateAll() {
        lock.lock()
        let sessions = activeSessions.values
        activeSessions.removeAll()
        lock.unlock()

        for session in sessions {
            session.terminate()
        }
    }

    /// Returns the number of currently active exec sessions.
    var activeSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions.count
    }
}
