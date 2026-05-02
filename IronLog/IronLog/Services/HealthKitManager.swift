import Foundation
import HealthKit

/// Manages HealthKit integration for saving strength training workouts.
final class HealthKitManager {

    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    private init() {}

    // MARK: - Authorization

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() {
        guard isAvailable else { return }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        // Read access for heart rate so the cycling executor can show
        // live BPM regardless of which app records the workout on the
        // watch (Apple Fitness, Strava, IronLogWatch, etc.).
        var typesToRead: Set<HKObjectType> = []
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(hrType)
        }

        store.requestAuthorization(
            toShare: typesToWrite,
            read: typesToRead
        ) { _, _ in }
    }

    // MARK: - Save Workout

    func saveWorkout(
        startDate: Date,
        endDate: Date,
        totalVolume: Double,
        totalSets: Int,
        templateName: String,
        planName: String?
    ) {
        guard isAvailable else { return }

        var metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "IronLog",
            "templateName": templateName,
            "totalVolumeKg": totalVolume,
            "totalSets": totalSets
        ]

        if let planName {
            metadata["planName"] = planName
        }

        let workout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: metadata
        )

        store.save(workout) { _, _ in }
    }
}
