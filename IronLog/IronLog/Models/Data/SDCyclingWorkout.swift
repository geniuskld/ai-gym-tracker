import Foundation
import SwiftData

@Model
final class SDCyclingWorkout {
    var workoutId: String
    var planType: String = "cycling"
    var planId: String?
    var planName: String?
    var planVersion: Int?
    var templateId: String
    var templateName: String

    var startedAt: Date
    var finishedAt: Date?
    var totalDurationSeconds: Int = 0

    var hadHrSource: Bool = false
    var averageHr: Int?
    var maxHr: Int?
    var calories: Int?

    var workoutNotes: String?
    var perceivedEffort: Int?
    var syncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SDCyclingSegmentLog.workout)
    var segments: [SDCyclingSegmentLog]

    init(
        workoutId: String = UUID().uuidString,
        planId: String? = nil,
        planName: String? = nil,
        planVersion: Int? = nil,
        templateId: String,
        templateName: String,
        startedAt: Date = .now
    ) {
        self.workoutId = workoutId
        self.planId = planId
        self.planName = planName
        self.planVersion = planVersion
        self.templateId = templateId
        self.templateName = templateName
        self.startedAt = startedAt
        self.segments = []
    }
}
