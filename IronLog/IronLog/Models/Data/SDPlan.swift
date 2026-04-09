import Foundation
import SwiftData

@Model
final class SDPlan {
    var planType: String = "strength"
    var planId: String = ""
    var planName: String
    @Attribute(originalName: "planVersion")
    var planVersion: Int = 1
    var schema: String = ""
    var createdAt: Date
    var importedAt: Date
    var author: String?
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \SDTemplate.plan)
    var templates: [SDTemplate]

    init(
        planType: String = "strength",
        planId: String,
        planName: String,
        planVersion: Int = 1,
        createdAt: Date,
        importedAt: Date = .now,
        author: String? = nil,
        notes: String? = nil
    ) {
        self.planType = planType
        self.planId = planId
        self.planName = planName
        self.planVersion = planVersion
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.author = author
        self.notes = notes
        self.templates = []
    }

    var isSupported: Bool {
        guard PlanType(rawValue: planType) != nil else { return false }
        guard !templates.isEmpty else { return false }
        for template in templates {
            guard !template.groups.isEmpty else { return false }
            for group in template.groups {
                guard !group.exercises.isEmpty else { return false }
                for exercise in group.exercises {
                    guard BodyPart(rawValue: exercise.bodyPart) != nil else { return false }
                    guard Technique(rawValue: exercise.technique) != nil else { return false }
                    guard !exercise.prescribedSets.isEmpty else { return false }
                }
            }
        }
        return true
    }
}
