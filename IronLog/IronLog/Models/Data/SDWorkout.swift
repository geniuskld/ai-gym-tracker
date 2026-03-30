import Foundation
import SwiftData

@Model
final class SDWorkout {
    var workoutId: String
    var templateId: String
    var templateName: String
    var planName: String?
    var startedAt: Date
    var finishedAt: Date?
    var durationMinutes: Double?
    var workoutNotes: String?
    var perceivedEffort: Int?

    @Relationship(deleteRule: .cascade, inverse: \SDExerciseLog.workout)
    var exercises: [SDExerciseLog]

    init(
        workoutId: String = UUID().uuidString,
        templateId: String,
        templateName: String,
        planName: String? = nil,
        startedAt: Date = .now
    ) {
        self.workoutId = workoutId
        self.templateId = templateId
        self.templateName = templateName
        self.planName = planName
        self.startedAt = startedAt
        self.exercises = []
    }
}
