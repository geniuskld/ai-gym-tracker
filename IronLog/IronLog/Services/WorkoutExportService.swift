import Foundation

enum WorkoutExportService {

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
                    exerciseName: ex.exerciseName,
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
