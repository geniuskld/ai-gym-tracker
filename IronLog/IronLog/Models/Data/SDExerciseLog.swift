import Foundation
import SwiftData

@Model
final class SDExerciseLog {
    var exerciseId: String
    var exerciseName: String
    var order: Int
    var exerciseNotes: String?
    var exerciseRating: Int?

    var workout: SDWorkout?

    @Relationship(deleteRule: .cascade, inverse: \SDSetLog.exerciseLog)
    var sets: [SDSetLog]

    init(
        exerciseId: String,
        exerciseName: String,
        order: Int = 0,
        exerciseNotes: String? = nil
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.exerciseNotes = exerciseNotes
        self.sets = []
    }
}
