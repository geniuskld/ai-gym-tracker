import Foundation

// MARK: - Cycling Plan (import schema mirror)

struct CyclingPlanJSON: Codable {
    let planType: PlanType            // always .cycling
    let planId: String
    let planName: String
    let planVersion: Int
    let schema: String?
    let createdAt: Date
    let author: String?
    let notes: String?
    let maxHrBpm: Int?
    let templates: [CyclingTemplateJSON]

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case planId = "plan_id"
        case planName = "plan_name"
        case planVersion = "plan_version"
        case schema
        case createdAt = "created_at"
        case author
        case notes
        case maxHrBpm = "max_hr_bpm"
        case templates
    }
}

struct CyclingTemplateJSON: Codable {
    let id: String
    let name: String
    let equipment: CyclingEquipment?
    let notes: String?
    let progression: CyclingProgressionJSON?
    let segments: [CyclingSegmentJSON]
}

/// Self-referential: leaf segments have `durationSeconds` + `target`,
/// `interval_block` segments have `repeats` + `children`.
struct CyclingSegmentJSON: Codable {
    let kind: CyclingSegmentKind
    let name: String
    let notes: String?

    // Leaf-only
    let durationSeconds: Int?
    let target: CyclingTargetJSON?

    // Block-only
    let repeats: Int?
    let children: [CyclingSegmentJSON]?

    enum CodingKeys: String, CodingKey {
        case kind, name, notes
        case durationSeconds = "duration_seconds"
        case target, repeats, children
    }
}

struct CyclingTargetJSON: Codable {
    let type: CyclingTargetType
    let min: Int?
    let max: Int?
    let zoneLabel: String?

    enum CodingKeys: String, CodingKey {
        case type, min, max
        case zoneLabel = "zone_label"
    }
}

struct CyclingProgressionJSON: Codable {
    let axis: CyclingProgressionAxis?
    let step: CyclingProgressionStepJSON?
    let advanceWhen: String?

    enum CodingKeys: String, CodingKey {
        case axis, step
        case advanceWhen = "advance_when"
    }
}

struct CyclingProgressionStepJSON: Codable {
    let intervalsDelta: Int?
    let workDurationSeconds: Int?
    let hrBpmDelta: Int?

    enum CodingKeys: String, CodingKey {
        case intervalsDelta = "intervals_delta"
        case workDurationSeconds = "work_duration_seconds"
        case hrBpmDelta = "hr_bpm_delta"
    }
}

// MARK: - Enums

enum CyclingEquipment: String, Codable {
    case stationaryBike = "stationary_bike"
    case spinBike = "spin_bike"
    case outdoorBike = "outdoor_bike"
}

enum CyclingSegmentKind: String, Codable {
    case warmup, work, recovery, cooldown, steady
    case intervalBlock = "interval_block"

    var isLeaf: Bool { self != .intervalBlock }
}

enum CyclingTargetType: String, Codable {
    case hrBpmRange = "hr_bpm_range"
    case rpe
    case free
}

enum CyclingProgressionAxis: String, Codable {
    case intervals
    case workDuration = "work_duration"
    case intensityHr = "intensity_hr"
    case manual
}
