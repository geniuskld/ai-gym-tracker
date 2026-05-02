import Foundation
import HealthKit

/// Live heart-rate source for cardio workouts.
///
/// Phase 1 ships only `NoHRSource` (always nil). Phase 2 will add a
/// `WatchHRSource` that talks to IronLogWatch via WatchConnectivity and
/// streams HR samples from `HKLiveWorkoutBuilder`. The executor view
/// reads `currentBpm` once per second; `nil` means "no source" or "not
/// yet sampled" -- the UI treats both the same way.
@MainActor
protocol HRSource: AnyObject {
    var isAvailable: Bool { get }
    var currentBpm: Int? { get }
    /// Last sample timestamp; UI can dim the value if it goes stale.
    var lastSampleAt: Date? { get }

    func start()
    func stop()
}

/// Default no-op source. Always reports unavailable.
@MainActor
final class NoHRSource: HRSource {
    var isAvailable: Bool { false }
    var currentBpm: Int? { nil }
    var lastSampleAt: Date? { nil }
    func start() {}
    func stop() {}
}

/// Resolves the best available HR source for the device.
///
/// Priority (in order of HR-stream quality):
///   1. `WatchHRSource` -- if IronLogWatch companion is installed AND
///      reachable, this is the BEST path. WatchConnectivity streams HR
///      directly from `HKLiveWorkoutBuilder` on the watch, ~1 Hz, with
///      no Apple Health buffering at all.
///   2. `PhoneWorkoutHRSource` (iOS 26+) -- iPhone-owned cycling
///      `HKWorkoutSession`. In theory the Watch joins; in practice
///      reliable HR requires a watch-side workout app. Useful for
///      flagging the workout to Apple Activity rings.
///   3. `HealthKitHRSource` -- passive observer over Apple Health.
///      Receives whatever any watch app pushes; Apple Fitness buffers
///      30-60 s, so this path has visible latency.
///   4. `NoHRSource`.
@MainActor
enum HRSourceResolver {
    static func resolve() -> HRSource {
        if WorkoutSessionManager.shared.isWatchAvailable {
            return WatchHRSource()
        }
        if #available(iOS 26.0, *), HKHealthStore.isHealthDataAvailable() {
            return PhoneWorkoutHRSource()
        }
        if HKHealthStore.isHealthDataAvailable() {
            return HealthKitHRSource()
        }
        return NoHRSource()
    }
}
