import Foundation
import SwiftData

@Model
final class SDCyclingPlan {
    var planType: String = "cycling"
    var planId: String = ""
    var planName: String
    @Attribute(originalName: "planVersion")
    var planVersion: Int = 1
    var schema: String = ""
    var createdAt: Date
    var importedAt: Date
    var author: String?
    var notes: String?
    var maxHrBpm: Int?

    // Progression hooks (flattened: one progression per plan is enough for now;
    // it actually lives per-template in JSON but we mirror it as plan-level for
    // simpler queries -- the per-template copy is held inside SDCyclingTemplate).
    @Relationship(deleteRule: .cascade, inverse: \SDCyclingTemplate.plan)
    var templates: [SDCyclingTemplate]

    init(
        planId: String,
        planName: String,
        planVersion: Int = 1,
        schema: String = PlanSchema.cyclingId,
        createdAt: Date,
        importedAt: Date = .now,
        author: String? = nil,
        notes: String? = nil,
        maxHrBpm: Int? = nil
    ) {
        self.planId = planId
        self.planName = planName
        self.planVersion = planVersion
        self.schema = schema
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.author = author
        self.notes = notes
        self.maxHrBpm = maxHrBpm
        self.templates = []
    }

    /// Lightweight structural validation -- mirrors SDPlan.isSupported.
    var isSupported: Bool {
        guard !templates.isEmpty else { return false }
        for t in templates {
            guard !t.segments.isEmpty else { return false }
            for s in t.segments {
                guard CyclingSegmentKind(rawValue: s.kind) != nil else { return false }
                if s.kind == CyclingSegmentKind.intervalBlock.rawValue {
                    guard (s.repeats ?? 0) >= 1, !s.children.isEmpty else { return false }
                } else {
                    guard (s.durationSeconds ?? 0) >= 1 else { return false }
                }
            }
        }
        return true
    }
}
