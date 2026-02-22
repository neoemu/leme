import Foundation

// MARK: - TerminalSessionType

enum TerminalSessionType: Sendable, Hashable {
    case local
    case podExec(podName: String, namespace: String, container: String?)
}

// MARK: - TerminalSession

struct TerminalSession: Identifiable, Sendable, Hashable {
    let id: UUID
    let title: String
    let type: TerminalSessionType

    init(id: UUID = UUID(), title: String, type: TerminalSessionType) {
        self.id = id
        self.title = title
        self.type = type
    }
}

// MARK: - TerminalViewModel

@Observable
@MainActor
final class TerminalViewModel {
    var sessions: [TerminalSession] = []
    var activeSessionID: UUID?

    var activeSession: TerminalSession? {
        guard let id = activeSessionID else { return sessions.first }
        return sessions.first { $0.id == id }
    }

    // MARK: - Session Management

    @discardableResult
    func createLocalSession(kubeContext: String?) -> TerminalSession {
        let title = "local"
        let session = TerminalSession(title: title, type: .local)
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    @discardableResult
    func createPodExecSession(
        podName: String,
        namespace: String,
        container: String?,
        kubeContext: String?
    ) -> TerminalSession {
        let title = podName
        let session = TerminalSession(
            title: title,
            type: .podExec(podName: podName, namespace: namespace, container: container)
        )
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    func closeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
    }

    func closeAllSessions() {
        sessions.removeAll()
        activeSessionID = nil
    }
}
