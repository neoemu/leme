import Foundation

/// Runs the `helm` CLI against a specific kube-context, mirroring the kubectl
/// subprocess handling in `KubernetesService` (auto `--kube-context`, temp-file
/// output buffers, termination handler set before launch).
struct HelmService: Sendable {
    let contextName: String?

    init(contextName: String?) {
        self.contextName = contextName
    }

    // MARK: - Releases

    /// Lists releases in a namespace, or across all namespaces when nil.
    func listReleases(namespace: String?) async throws -> [HelmRelease] {
        // helm 4 dropped `list --all`; the explicit state filters below exist
        // in both helm 3 and 4 and together cover every live state.
        var arguments = [
            "list",
            "--deployed", "--failed", "--pending", "--superseded", "--uninstalling",
            "--max", "10000", "-o", "json",
        ]
        if let namespace, !namespace.isEmpty {
            arguments.append(contentsOf: ["-n", namespace])
        } else {
            arguments.append("--all-namespaces")
        }
        let output = try await executeHelm(arguments: arguments)
        return try Self.parseReleases(output.stdout)
    }

    func history(releaseName: String, namespace: String) async throws -> [HelmReleaseRevision] {
        let output = try await executeHelm(
            arguments: ["history", releaseName, "-n", namespace, "--max", "50", "-o", "json"]
        )
        return try Self.parseHistory(output.stdout)
    }

    /// User-supplied values by default; computed values with `allValues`.
    /// `revision` nil means the latest revision.
    func values(releaseName: String, namespace: String, allValues: Bool, revision: Int? = nil) async throws -> String {
        var arguments = ["get", "values", releaseName, "-n", namespace, "-o", "yaml"]
        if allValues {
            arguments.append("--all")
        }
        if let revision {
            arguments.append(contentsOf: ["--revision", String(revision)])
        }
        return try await executeHelm(arguments: arguments).stdout
    }

    func manifest(releaseName: String, namespace: String) async throws -> String {
        try await executeHelm(arguments: ["get", "manifest", releaseName, "-n", namespace]).stdout
    }

    func rollback(releaseName: String, toRevision revision: Int, namespace: String) async throws {
        _ = try await executeHelm(arguments: ["rollback", releaseName, String(revision), "-n", namespace])
    }

    func uninstall(releaseName: String, namespace: String) async throws {
        _ = try await executeHelm(arguments: ["uninstall", releaseName, "-n", namespace])
    }

    // MARK: - JSON parsing

    static func parseReleases(_ json: String) throws -> [HelmRelease] {
        let items: [ReleaseDTO] = try decodeList(json)
        return items.map { item in
            HelmRelease(
                name: item.name ?? "",
                namespace: item.namespace ?? "",
                revision: item.revision?.value ?? 0,
                updated: HelmTimestampParser.parse(item.updated ?? ""),
                status: item.status ?? "unknown",
                chart: item.chart ?? "",
                appVersion: item.appVersion ?? ""
            )
        }
    }

    static func parseHistory(_ json: String) throws -> [HelmReleaseRevision] {
        let items: [RevisionDTO] = try decodeList(json)
        return items.map { item in
            HelmReleaseRevision(
                revision: item.revision?.value ?? 0,
                updated: HelmTimestampParser.parse(item.updated ?? ""),
                status: item.status ?? "unknown",
                chart: item.chart ?? "",
                appVersion: item.appVersion ?? "",
                description: item.description ?? ""
            )
        }
    }

    private static func decodeList<T: Decodable>(_ json: String) throws -> [T] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([T].self, from: Data(trimmed.utf8))
    }

    struct ReleaseDTO: Decodable {
        let name: String?
        let namespace: String?
        let revision: FlexibleInt?
        let updated: String?
        let status: String?
        let chart: String?
        let appVersion: String?
    }

    struct RevisionDTO: Decodable {
        let revision: FlexibleInt?
        let updated: String?
        let status: String?
        let chart: String?
        let appVersion: String?
        let description: String?
    }

    /// `helm list` emits revision as a string, `helm history` as a number.
    struct FlexibleInt: Decodable {
        let value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                value = intValue
            } else if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
                value = intValue
            } else {
                value = 0
            }
        }
    }

    // MARK: - Subprocess execution

    private struct HelmCommandOutput {
        let stdout: String
        let stderr: String
    }

    private func executeHelm(arguments: [String]) async throws -> HelmCommandOutput {
        let helmPath = try findHelm()

        var arguments = arguments
        if let contextName, !contextName.isEmpty, !arguments.contains("--kube-context") {
            arguments.append(contentsOf: ["--kube-context", contextName])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helmPath)
        process.arguments = arguments

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent("klaro-helm-stdout-\(UUID().uuidString).tmp")
        let stderrURL = tempDirectory.appendingPathComponent("klaro-helm-stderr-\(UUID().uuidString).tmp")

        guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: stderrURL.path, contents: nil),
              let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
              let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path) else {
            throw KubernetesServiceError.operationFailed("Failed to create helm output buffers.")
        }

        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        var environment = ProcessInfo.processInfo.environment
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        } else {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = environment

        let terminationStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: KubernetesOperationError(
                    category: .connectivity,
                    detail: "Failed to start helm: \(error.localizedDescription)"
                ))
            }
        }

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard terminationStatus == 0 else {
            let detail = stderr.isEmpty ? stdout : stderr
            let message = detail.isEmpty
                ? "helm command failed with exit code \(terminationStatus)"
                : detail

            throw KubernetesOperationError(
                category: KubernetesService.classifyOperationError(detail: message),
                detail: message
            )
        }

        return HelmCommandOutput(stdout: stdout, stderr: stderr)
    }

    private func findHelm() throws -> String {
        let commonPaths = [
            "/opt/homebrew/bin/helm",
            "/usr/local/bin/helm",
            "/usr/bin/helm",
            "/opt/local/bin/helm",
        ]

        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["helm"]
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // fall through to error
        }

        throw KubernetesServiceError.operationFailed(
            "helm not found. Install helm and ensure it is in PATH."
        )
    }
}
