import Foundation
import SwiftData

@Model
final class SDPlan {
    var planType: String = "strength"
    var planId: String = ""
    var planName: String
    @Attribute(originalName: "planVersion")
    var planVersion: Int = 1
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
}
