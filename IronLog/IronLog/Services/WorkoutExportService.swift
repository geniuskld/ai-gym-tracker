import Foundation

enum WorkoutExportService {

    // MARK: - Cycling

    /// Top-level JSON envelope ready for ShareLink / clipboard copy.
    /// Mirrors `exportJSON` for strength: same envelope shape, just
    /// cycling-flavoured payload inside `workouts[]`.
    static func exportCyclingJSON(_ workout: SDCyclingWorkout) -> String {
        let envelope = CyclingLogEnvelopeJSON(
            version: "1.0",
            exportedAt: .now,
            workouts: [cyclingWorkoutToJSON(workout)]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(envelope),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{ \"error\": \"encoding failed\" }"
        }
        return str
    }

    static func cyclingWorkoutToJSON(_ w: SDCyclingWorkout) -> CyclingWorkoutJSON {
        let segs = w.segments
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { s in
                CyclingSegmentLogJSON(
                    segmentPath: s.segmentPath,
                    kind: s.kind,
                    name: s.name,
                    durationSecondsActual: s.durationSecondsActual,
                    targetMinBpm: s.targetMinBpm,
                    targetMaxBpm: s.targetMaxBpm,
                    averageHr: s.averageHr,
                    maxHr: s.maxHr,
                    inZoneSeconds: s.inZoneSeconds,
                    inZonePct: s.inZonePct,
                    skipped: s.skipped
                )
            }

        return CyclingWorkoutJSON(
            id: w.workoutId,
            planType: w.planType,
            planId: w.planId,
            planName: w.planName,
            planVersion: w.planVersion,
            templateId: w.templateId,
            templateName: w.templateName,
            startedAt: w.startedAt,
            finishedAt: w.finishedAt,
            totalDurationSeconds: w.totalDurationSeconds,
            hadHrSource: w.hadHrSource,
            averageHr: w.averageHr,
            maxHr: w.maxHr,
            calories: w.calories,
            workoutNotes: w.workoutNotes,
            perceivedEffort: w.perceivedEffort,
            segments: segs
        )
    }

    // MARK: - Strength

    static func exportJSON(_ workout: SDWorkout) -> String {
        let log = WorkoutLogJSON(
            version: "1.0",
            exportedAt: .now,
            exportRange: nil,
            userProfile: nil,
            workouts: [workoutToJSON(workout)]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(log),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{ \"error\": \"encoding failed\" }"
        }
        return str
    }

    static func workoutToJSON(_ w: SDWorkout) -> WorkoutJSON {
        let exerciseLogs = w.exercises
            .sorted { $0.order < $1.order }
            .map { ex in
                ExerciseLogJSON(
                    exerciseId: ex.exerciseId,
                    catalogId: ex.catalogId,
                    exerciseName: ex.exerciseName,
                    bodyPart: ex.bodyPart,
                    order: ex.order,
                    sets: ex.sets
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { s in
                            SetLogJSON(
                                setNumber: s.setNumber,
                                setType: LogSetType(rawValue: s.setType),
                                weightKg: s.weightKg,
                                reps: s.reps,
                                rpe: s.rpe,
                                rir: s.rir,
                                restSecondsAfter: s.restSecondsAfter,
                                setDurationSeconds: s.setDurationSeconds,
                                isPr: s.isPr ? true : nil,
                                failed: s.failed ? true : nil,
                                notes: s.notes
                            )
                        },
                    exerciseNotes: ex.exerciseNotes,
                    exerciseRating: ex.exerciseRating
                )
            }

        return WorkoutJSON(
            id: w.workoutId,
            templateId: w.templateId,
            templateName: w.templateName,
            planType: w.planType,
            planId: w.planId,
            planName: w.planName,
            planVersion: w.planVersion,
            startedAt: w.startedAt,
            finishedAt: w.finishedAt,
            durationMinutes: w.durationMinutes,
            workoutNotes: w.workoutNotes,
            perceivedEffort: w.perceivedEffort,
            exercises: exerciseLogs
        )
    }
}
