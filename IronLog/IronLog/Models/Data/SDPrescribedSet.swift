import Foundation
import SwiftData

@Model
final class SDPrescribedSet {
    var type: String
    var reps: Int?
    /// Stored as Double to support fractional plate increments (e.g. 102.5 kg).
    /// Schema bumped on 2026-04-29 from Int to Double; old stores require wipe.
    var weightKg: Double?
    var rir: Int?
    var weightPercentDrop: Double?
    var sortOrder: Int

    var exercise: SDExercise?

    init(
        type: String = "working",
        reps: Int? = nil,
        weightKg: Double? = nil,
        rir: Int? = nil,
        weightPercentDrop: Double? = nil,
        sortOrder: Int = 0
    ) {
        self.type = type
        self.reps = reps
        self.weightKg = weightKg
        self.rir = rir
        self.weightPercentDrop = weightPercentDrop
        self.sortOrder = sortOrder
    }
}
