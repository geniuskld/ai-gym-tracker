import Foundation
import SwiftData

@Model
final class SDPlan {
    var planName: String
    var createdAt: Date
    var importedAt: Date
    var author: String?
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \SDTemplate.plan)
    var templates: [SDTemplate]

    init(
        planName: String,
        createdAt: Date,
        importedAt: Date = .now,
        author: String? = nil,
        notes: String? = nil
    ) {
        self.planName = planName
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.author = author
        self.notes = notes
        self.templates = []
    }
}
