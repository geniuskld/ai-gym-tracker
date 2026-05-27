import Foundation
import SwiftData

@Model
final class SDExerciseLog {
    var exerciseId: String
    var catalogId: String?
    var exerciseName: String
    var bodyPart: String?
    var order: Int
    var technique: String?
    var supersetWith: String?
    var exerciseNotes: String?
    var exerciseRating: Int?

    var workout: SDWorkout?

    @Relationship(deleteRule: .cascade, inverse: \SDSetLog.exerciseLog)
    var sets: [SDSetLog]

    init(
        exerciseId: String,
        catalogId: String? = nil,
        exerciseName: String,
        bodyPart: String? = nil,
        order: Int = 0,
        technique: String? = nil,
        supersetWith: String? = nil,
        exerciseNotes: String? = nil
    ) {
        self.exerciseId = exerciseId
        self.catalogId = catalogId
        self.exerciseName = exerciseName
        self.bodyPart = bodyPart
        self.order = order
        self.technique = technique
        self.supersetWith = supersetWith
        self.exerciseNotes = exerciseNotes
        self.sets = []
    }
}
