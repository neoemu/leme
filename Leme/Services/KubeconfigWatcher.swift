import Foundation

/// Watches the kubeconfig file for changes via a DispatchSource and invokes a
/// callback after edits. Re-arms automatically when the file is replaced
/// atomically (rename/delete), which is how most tools rewrite kubeconfig.
final class KubeconfigWatcher: @unchecked Sendable {

    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.leme.kubeconfig-watcher")

    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    private static let debounceInterval: TimeInterval = 0.5
    private static let missingFileRetryInterval: TimeInterval = 2.0

    init(
        path: String = Constants.defaultKubeconfigPath,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.path = (path as NSString).expandingTildeInPath
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            self?.arm()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.disarm()
        }
    }

    // MARK: - Private

    private func arm() {
        disarm()

        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            // File missing (for example mid-replace); retry shortly.
            queue.asyncAfter(deadline: .now() + Self.missingFileRetryInterval) { [weak self] in
                self?.arm()
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            self.scheduleNotify()
            if events.contains(.rename) || events.contains(.delete) {
                // The fd now points at the old inode; re-open the new file.
                self.arm()
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        self.source = source
        source.resume()
    }

    private func disarm() {
        source?.cancel()
        source = nil
    }

    private func scheduleNotify() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [onChange] in
            onChange()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }
}
