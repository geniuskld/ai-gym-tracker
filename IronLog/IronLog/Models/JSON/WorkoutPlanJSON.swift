import Foundation

// MARK: - Workout Plan (import schema mirror)

struct WorkoutPlanJSON: Codable {
    let version: String
    let planName: String
    let createdAt: Date
    let author: String?
    let notes: String?
    let templates: [TemplateJSON]

    enum CodingKeys: String, CodingKey {
        case version
        case planName = "plan_name"
        case createdAt = "created_at"
        case author
        case notes
        case templates
    }
}

struct TemplateJSON: Codable {
    let id: String
    let name: String
    let notes: String?
    let groups: [ExerciseGroupJSON]
}

struct ExerciseGroupJSON: Codable {
    let name: String
    let exercises: [ExerciseJSON]
}

struct ExerciseJSON: Codable {
    let id: String
    let name: String
    let bodyPart: BodyPart
    let equipment: Equipment?
    let sets: [PrescribedSetJSON]
    let restSeconds: Int?
    let technique: Technique?
    let supersetWith: String?
    let tempo: String?
    let notes: String?
    let stretchFocus: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case bodyPart = "body_part"
        case equipment, sets
        case restSeconds = "rest_seconds"
        case technique
        case supersetWith = "superset_with"
        case tempo, notes
        case stretchFocus = "stretch_focus"
    }
}

struct PrescribedSetJSON: Codable {
    let type: SetType?
    let reps: Int?
    let rir: Int?
    let weightPercentDrop: Double?

    enum CodingKeys: String, CodingKey {
        case type, reps, rir
        case weightPercentDrop = "weight_percent_drop"
    }
}

// MARK: - Enums

enum BodyPart: String, Codable {
    case chest, back, shoulders, legs, arms, core
    case fullBody = "full_body"
}

enum Equipment: String, Codable {
    case machine, barbell, dumbbell, cable, bodyweight
    case plateLoaded = "plate_loaded"
    case smithMachine = "smith_machine"
    case other
}

enum SetType: String, Codable {
    case warmup, working, drop, backoff
}

enum Technique: String, Codable {
    case straight
    case dropSet = "drop_set"
    case restPause = "rest_pause"
    case myoReps = "myo_reps"
    case superset
}
