import Foundation
import SwiftData

@Model
final class SDSetLog {
    var setNumber: Int
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var rpe: Double?
    var rir: Int?
    var restSecondsAfter: Int?
    var isPr: Bool
    var failed: Bool
    var notes: String?

    var exerciseLog: SDExerciseLog?

    init(
        setNumber: Int,
        setType: String = "working",
        weightKg: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        rir: Int? = nil,
        restSecondsAfter: Int? = nil,
        isPr: Bool = false,
        failed: Bool = false,
        notes: String? = nil
    ) {
        self.setNumber = setNumber
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.restSecondsAfter = restSecondsAfter
        self.isPr = isPr
        self.failed = failed
        self.notes = notes
    }
}
