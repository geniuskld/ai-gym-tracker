import Foundation
import SwiftData

@Model
final class SDExerciseLog {
    var exerciseId: String
    var catalogId: String?
    var exerciseName: String
    var bodyPart: String?
    var order: Int
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
        exerciseNotes: String? = nil
    ) {
        self.exerciseId = exerciseId
        self.catalogId = catalogId
        self.exerciseName = exerciseName
        self.bodyPart = bodyPart
        self.order = order
        self.exerciseNotes = exerciseNotes
        self.sets = []
    }
}
