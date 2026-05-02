import Foundation
import SwiftData

@Model
final class SDCyclingTemplate {
    var templateId: String
    var name: String
    var equipment: String?
    var notes: String?
    var sortOrder: Int

    // Progression hints (optional, free-form; app may show advance_when as text)
    var progressionAxis: String?
    var progressionStepIntervalsDelta: Int?
    var progressionStepWorkDurationSeconds: Int?
    var progressionStepHrBpmDelta: Int?
    var progressionAdvanceWhen: String?

    var plan: SDCyclingPlan?

    /// Top-level segments only. Each segment may itself own children
    /// (when kind == "interval_block").
    @Relationship(deleteRule: .cascade, inverse: \SDCyclingSegment.template)
    var segments: [SDCyclingSegment]

    init(
        templateId: String,
        name: String,
        equipment: String? = nil,
        notes: String? = nil,
        sortOrder: Int = 0
    ) {
        self.templateId = templateId
        self.name = name
        self.equipment = equipment
        self.notes = notes
        self.sortOrder = sortOrder
        self.segments = []
    }
}
