import Foundation
import SwiftData

@Model
final class SDTemplate {
    var templateId: String
    var name: String
    var notes: String?
    var sortOrder: Int

    var plan: SDPlan?

    @Relationship(deleteRule: .cascade, inverse: \SDExerciseGroup.template)
    var groups: [SDExerciseGroup]

    init(
        templateId: String,
        name: String,
        notes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.templateId = templateId
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.groups = []
    }
}
