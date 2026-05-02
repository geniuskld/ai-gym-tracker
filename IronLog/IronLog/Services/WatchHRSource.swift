import Foundation

/// HRSource backed by an Apple Watch streaming HR samples via
/// WatchConnectivity. Registers as an `HRSampleListener` on the shared
/// `WorkoutSessionManager`; samples flow in roughly once per second from
/// the Watch's `HKLiveWorkoutBuilder`.
///
/// `currentBpm` returns nil until the first sample arrives -- the executor
/// shows that state as "waiting" / dimmed. If no Watch is paired or the
/// session isn't activated, callers should pick `NoHRSource` instead via
/// `HRSourceResolver`.
@MainActor
final class WatchHRSource: HRSource, HRSampleListener {

    private(set) var currentBpm: Int?
    private(set) var lastSampleAt: Date?

    var isAvailable: Bool {
        WorkoutSessionManager.shared.isWatchAvailable
    }

    func start() {
        WorkoutSessionManager.shared.registerHRListener(self)
        WorkoutSessionManager.shared.startMirroringCardio()
    }

    func stop() {
        WorkoutSessionManager.shared.unregisterHRListener(self)
        WorkoutSessionManager.shared.stopMirroring()
    }

    // MARK: - HRSampleListener

    func didReceiveHRSample(bpm: Int, at: Date) {
        guard bpm > 0 else { return }
        currentBpm = bpm
        lastSampleAt = at
    }
}
