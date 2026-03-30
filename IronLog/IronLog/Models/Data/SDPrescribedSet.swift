import Foundation
import SwiftData

@Model
final class SDPrescribedSet {
    var type: String
    var reps: Int?
    var weightKg: Int?
    var rir: Int?
    var weightPercentDrop: Double?
    var sortOrder: Int

    var exercise: SDExercise?

    init(
        type: String = "working",
        reps: Int? = nil,
        weightKg: Int? = nil,
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
