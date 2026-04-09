import Foundation
import SwiftData

@Model
final class SDWorkout {
    var workoutId: String
    var templateId: String
    var templateName: String
    var planType: String?
    var planId: String?
    var planName: String?
    var planVersion: Int?
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
        planType: String? = nil,
        planId: String? = nil,
        planName: String? = nil,
        planVersion: Int? = nil,
        startedAt: Date = .now
    ) {
        self.workoutId = workoutId
        self.templateId = templateId
        self.templateName = templateName
        self.planType = planType
        self.planId = planId
        self.planName = planName
        self.planVersion = planVersion
        self.startedAt = startedAt
        self.exercises = []
    }
}
