import Foundation
import SwiftData

@Model
final class SDPrescribedSet {
    var type: String
    var repsMin: Int?
    var repsMax: Int?
    var rir: Int?
    var weightPercentDrop: Double?
    var sortOrder: Int

    var exercise: SDExercise?

    init(
        type: String = "working",
        repsMin: Int? = nil,
        repsMax: Int? = nil,
        rir: Int? = nil,
        weightPercentDrop: Double? = nil,
        sortOrder: Int = 0
    ) {
        self.type = type
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.rir = rir
        self.weightPercentDrop = weightPercentDrop
        self.sortOrder = sortOrder
    }
}
