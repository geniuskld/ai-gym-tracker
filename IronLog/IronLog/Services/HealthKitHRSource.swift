import Foundation
import HealthKit

/// Live heart-rate source that subscribes to Apple Health's `.heartRate`
/// stream via `HKAnchoredObjectQuery`. Works regardless of which app is
/// recording the underlying workout on the watch -- if Apple Workout
/// (Fitness), Strava, Garmin Connect, or our own IronLogWatch is running
/// an `HKWorkoutSession`, the watch pumps HR samples (~1 Hz) into Health
/// and we receive them here within a second or two.
///
/// Crucially this means the user does NOT have to start IronLogWatch
/// specifically -- they can keep using whatever workout app they prefer
/// on the watch, and live HR shows up in IronLog's cycling executor.
///
/// Privacy note: HealthKit does not expose whether read auth was granted
/// (Apple intentionally hides this to prevent fingerprinting). So we
/// always set up the query; if the user denied access, samples simply
/// never arrive and `currentBpm` stays nil. The UI handles this the same
/// way as "no watch on wrist" -- shows the fallback message.
@MainActor
final class HealthKitHRSource: HRSource {

    private let store = HKHealthStore()
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let bpmUnit = HKUnit(from: "count/min")

    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    private(set) var currentBpm: Int?
    private(set) var lastSampleAt: Date?

    var isAvailable: Bool {
        // We can't directly know if read auth was granted -- assume yes
        // when Health is available on the device. Worst case: samples
        // never arrive and the UI shows the fallback message.
        HKHealthStore.isHealthDataAvailable()
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        stop()

        // Only consider samples from the last 60 seconds going forward.
        // Stale samples from hours ago are useless for "live HR in zone"
        // and would mislead the colour indicator.
        let predicate = HKQuery.predicateForSamples(
            withStart: Date.now.addingTimeInterval(-60),
            end: nil,
            options: .strictStartDate
        )

        let q = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            Task { @MainActor in
                self.consume(samples)
                self.anchor = newAnchor
            }
        }
        // Stream subsequent samples as they arrive.
        q.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            Task { @MainActor in
                self.consume(samples)
                self.anchor = newAnchor
            }
        }
        store.execute(q)
        self.query = q
    }

    func stop() {
        if let q = query {
            store.stop(q)
        }
        query = nil
        anchor = nil
    }

    // MARK: - Internal

    /// Take the most recent HR sample from the batch. Apple Health may
    /// deliver several samples in one update (especially after the watch
    /// has been backgrounded) -- we want the LATEST one.
    private func consume(_ samples: [HKSample]?) {
        guard let qs = samples as? [HKQuantitySample], !qs.isEmpty else { return }
        guard let latest = qs.max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = Int(latest.quantity.doubleValue(for: bpmUnit).rounded())
        guard bpm > 0 else { return }
        currentBpm = bpm
        lastSampleAt = latest.endDate
    }
}
