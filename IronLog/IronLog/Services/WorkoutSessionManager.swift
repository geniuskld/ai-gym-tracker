import Foundation
import WatchConnectivity

// Sends start/stop workout commands to Apple Watch via WatchConnectivity.
// The watchOS app receives the message and starts HKWorkoutSession locally.
@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {

    static let shared = WorkoutSessionManager()

    @Published var isMirroring = false

    private var wcSession: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    func startMirroring() {
        guard let session = wcSession,
              session.isReachable
        else { return }

        session.sendMessage(
            ["command": "startWorkout"],
            replyHandler: { _ in
                Task { @MainActor in
                    self.isMirroring = true
                }
            },
            errorHandler: { _ in
                // Watch not reachable -- ignore silently
            }
        )
    }

    func stopMirroring() {
        guard let session = wcSession,
              session.isReachable
        else {
            isMirroring = false
            return
        }

        session.sendMessage(
            ["command": "stopWorkout"],
            replyHandler: nil,
            errorHandler: nil
        )
        isMirroring = false
    }
}

// MARK: - WCSessionDelegate

extension WorkoutSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
