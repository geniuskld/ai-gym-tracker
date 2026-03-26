import Foundation

// MARK: - Workout Log (export schema mirror)

struct WorkoutLogJSON: Codable {
    let version: String
    let exportedAt: Date
    let exportRange: ExportRange?
    let userProfile: UserProfile?
    let workouts: [WorkoutJSON]

    enum CodingKeys: String, CodingKey {
        case version
        case exportedAt = "exported_at"
        case exportRange = "export_range"
        case userProfile = "user_profile"
        case workouts
    }
}

struct ExportRange: Codable {
    let from: String?
    let to: String?
}

struct UserProfile: Codable {
    let bodyWeightKg: Double?
    let heightCm: Int?
    let age: Int?
    let trainingGoal: TrainingGoal?

    enum CodingKeys: String, CodingKey {
        case bodyWeightKg = "body_weight_kg"
        case heightCm = "height_cm"
        case age
        case trainingGoal = "training_goal"
    }
}

enum TrainingGoal: String, Codable {
    case hypertrophy, strength, endurance, recomp, general
}

struct WorkoutJSON: Codable {
    let id: String
    let templateId: String
    let templateName: String?
    let startedAt: Date
    let finishedAt: Date?
    let durationMinutes: Double?
    let workoutNotes: String?
    let perceivedEffort: Int?
    let exercises: [ExerciseLogJSON]

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case templateName = "template_name"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case durationMinutes = "duration_minutes"
        case workoutNotes = "workout_notes"
        case perceivedEffort = "perceived_effort"
        case exercises
    }
}

struct ExerciseLogJSON: Codable {
    let exerciseId: String
    let exerciseName: String
    let order: Int?
    let sets: [SetLogJSON]
    let exerciseNotes: String?

    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case order, sets
        case exerciseNotes = "exercise_notes"
    }
}

struct SetLogJSON: Codable {
    let setNumber: Int
    let setType: LogSetType?
    let weightKg: Double?
    let reps: Int?
    let rpe: Double?
    let rir: Int?
    let restSecondsAfter: Int?
    let isPr: Bool?
    let failed: Bool?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case setType = "set_type"
        case weightKg = "weight_kg"
        case reps, rpe, rir
        case restSecondsAfter = "rest_seconds_after"
        case isPr = "is_pr"
        case failed, notes
    }
}

enum LogSetType: String, Codable {
    case warmup, working, drop
    case myoActivation = "myo_activation"
    case myoMini = "myo_mini"
    case rpInitial = "rp_initial"
    case rpContinuation = "rp_continuation"
    case backoff
}
