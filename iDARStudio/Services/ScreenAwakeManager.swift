import UIKit

@MainActor
final class ScreenAwakeManager {
    enum SessionKind: String, Sendable {
        case object
        case room
        case environment
    }

    enum EndReason: String, Sendable {
        case stopped
        case cancelled
        case completed
        case failed
        case backgrounded
    }

    struct Session: Hashable, Sendable {
        fileprivate let id: UUID
        let kind: SessionKind
    }

    static let shared = ScreenAwakeManager { isDisabled in
        UIApplication.shared.isIdleTimerDisabled = isDisabled
    }

    private let applyIdleTimerDisabled: (Bool) -> Void
    private var activeSessions: Set<Session> = []
    private var appliedValue = false

    init(applyIdleTimerDisabled: @escaping (Bool) -> Void) {
        self.applyIdleTimerDisabled = applyIdleTimerDisabled
    }

    var isKeepingScreenAwake: Bool {
        !activeSessions.isEmpty
    }

    var activeSessionCount: Int {
        activeSessions.count
    }

    @discardableResult
    func begin(_ kind: SessionKind) -> Session {
        let session = Session(id: UUID(), kind: kind)
        activeSessions.insert(session)
        synchronizeIdleTimer()
        return session
    }

    func end(_ session: Session, reason: EndReason) {
        _ = reason
        activeSessions.remove(session)
        synchronizeIdleTimer()
    }

    func applicationDidEnterBackground() {
        activeSessions.removeAll()
        synchronizeIdleTimer()
    }

    private func synchronizeIdleTimer() {
        let nextValue = !activeSessions.isEmpty
        guard nextValue != appliedValue else { return }
        appliedValue = nextValue
        applyIdleTimerDisabled(nextValue)
    }
}
