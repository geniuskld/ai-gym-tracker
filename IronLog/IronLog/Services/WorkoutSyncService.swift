import Foundation
import SwiftData

@MainActor
enum WorkoutSyncService {
    private static let retryCooldown: TimeInterval = 60
    private static var lastAttemptByKey: [String: Date] = [:]

    struct RetrySummary {
        var attempted = 0
        var succeeded = 0
        var failed = 0
    }

    @discardableResult
    static func uploadStrength(
        _ workout: SDWorkout,
        context: ModelContext,
        force: Bool = false
    ) async -> Bool {
        guard shouldAttempt(key: strengthKey(workout), syncedAt: workout.syncedAt, force: force) else {
            return false
        }
        markAttempt(key: strengthKey(workout))

        let log = WorkoutLogJSON(
            version: "1.0",
            exportedAt: .now,
            exportRange: nil,
            userProfile: nil,
            workouts: [WorkoutExportService.workoutToJSON(workout)]
        )

        do {
            try await SyncService.uploadLog(log)
            workout.syncedAt = .now
            try context.save()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func uploadCycling(
        _ workout: SDCyclingWorkout,
        context: ModelContext,
        force: Bool = false
    ) async -> Bool {
        guard shouldAttempt(key: cyclingKey(workout), syncedAt: workout.syncedAt, force: force) else {
            return false
        }
        markAttempt(key: cyclingKey(workout))

        let envelope = CyclingLogEnvelopeJSON(
            version: "1.0",
            exportedAt: .now,
            workouts: [WorkoutExportService.cyclingWorkoutToJSON(workout)]
        )

        do {
            try await SyncService.uploadCyclingLog(envelope)
            workout.syncedAt = .now
            try context.save()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func retryPending(
        context: ModelContext,
        force: Bool = false,
        limit: Int = 20
    ) async -> RetrySummary {
        guard SyncService.isConfigured, SyncService.isAuthenticated else {
            return RetrySummary()
        }

        var summary = RetrySummary()

        do {
            var strengthDescriptor = FetchDescriptor<SDWorkout>(
                predicate: #Predicate {
                    $0.finishedAt != nil && $0.syncedAt == nil
                },
                sortBy: [SortDescriptor(\.startedAt)]
            )
            strengthDescriptor.fetchLimit = limit

            for workout in try context.fetch(strengthDescriptor) {
                summary.attempted += 1
                if await uploadStrength(workout, context: context, force: force) {
                    summary.succeeded += 1
                } else {
                    summary.failed += 1
                }
            }

            var cyclingDescriptor = FetchDescriptor<SDCyclingWorkout>(
                predicate: #Predicate {
                    $0.finishedAt != nil && $0.syncedAt == nil
                },
                sortBy: [SortDescriptor(\.startedAt)]
            )
            cyclingDescriptor.fetchLimit = limit

            for workout in try context.fetch(cyclingDescriptor) {
                summary.attempted += 1
                if await uploadCycling(workout, context: context, force: force) {
                    summary.succeeded += 1
                } else {
                    summary.failed += 1
                }
            }
        } catch {
            summary.failed += 1
        }

        return summary
    }

    private static func shouldAttempt(
        key: String,
        syncedAt: Date?,
        force: Bool
    ) -> Bool {
        guard SyncService.isConfigured, SyncService.isAuthenticated else {
            return false
        }
        guard syncedAt == nil else { return false }
        guard !force else { return true }
        if let last = lastAttemptByKey[key],
           Date.now.timeIntervalSince(last) < retryCooldown {
            return false
        }
        return true
    }

    private static func markAttempt(key: String) {
        lastAttemptByKey[key] = .now
    }

    private static func strengthKey(_ workout: SDWorkout) -> String {
        "strength:\(workout.workoutId)"
    }

    private static func cyclingKey(_ workout: SDCyclingWorkout) -> String {
        "cycling:\(workout.workoutId)"
    }
}
