import Foundation

// MARK: - Cycling Workout Log (export schema)

/// Wrapper: matches the strength log format -- server's POST /log expects
/// `{ workouts: [...] }`. Cycling workouts ride alongside.
struct CyclingLogEnvelopeJSON: Codable {
    let version: String
    let exportedAt: Date
    let workouts: [CyclingWorkoutJSON]

    enum CodingKeys: String, CodingKey {
        case version
        case exportedAt = "exported_at"
        case workouts
    }
}

struct CyclingWorkoutJSON: Codable {
    let id: String
    let planType: String
    let planId: String?
    let planName: String?
    let planVersion: Int?
    let templateId: String
    let templateName: String?
    let startedAt: Date
    let finishedAt: Date?
    let totalDurationSeconds: Int
    let hadHrSource: Bool
    let averageHr: Int?
    let maxHr: Int?
    let calories: Int?
    let workoutNotes: String?
    let perceivedEffort: Int?
    let segments: [CyclingSegmentLogJSON]

    enum CodingKeys: String, CodingKey {
        case id
        case planType = "plan_type"
        case planId = "plan_id"
        case planName = "plan_name"
        case planVersion = "plan_version"
        case templateId = "template_id"
        case templateName = "template_name"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case totalDurationSeconds = "total_duration_seconds"
        case hadHrSource = "had_hr_source"
        case averageHr = "average_hr"
        case maxHr = "max_hr"
        case calories
        case workoutNotes = "workout_notes"
        case perceivedEffort = "perceived_effort"
        case segments
    }
}

struct CyclingSegmentLogJSON: Codable {
    let segmentPath: String
    let kind: String
    let name: String
    let durationSecondsActual: Int
    let targetMinBpm: Int?
    let targetMaxBpm: Int?
    let averageHr: Int?
    let maxHr: Int?
    let inZoneSeconds: Int?
    let inZonePct: Int?
    let skipped: Bool

    enum CodingKeys: String, CodingKey {
        case segmentPath = "segment_path"
        case kind, name
        case durationSecondsActual = "duration_seconds_actual"
        case targetMinBpm = "target_min_bpm"
        case targetMaxBpm = "target_max_bpm"
        case averageHr = "average_hr"
        case maxHr = "max_hr"
        case inZoneSeconds = "in_zone_seconds"
        case inZonePct = "in_zone_pct"
        case skipped
    }
}
