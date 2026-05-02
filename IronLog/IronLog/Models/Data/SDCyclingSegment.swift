import Foundation
import SwiftData

/// Self-referential segment: a top-level segment belongs to a template,
/// a child belongs to a parent (interval_block). Exactly one of
/// `template` / `parent` is set.
@Model
final class SDCyclingSegment {
    var sortOrder: Int
    var kind: String           // warmup | work | recovery | cooldown | steady | interval_block
    var name: String
    var notes: String?

    // Leaf-only
    var durationSeconds: Int?
    var targetType: String?    // hr_bpm_range | rpe | free
    var targetMin: Int?
    var targetMax: Int?
    var targetZoneLabel: String?

    // Block-only
    var repeats: Int?

    // Ownership: top-level has `template`, children have `parent`.
    var template: SDCyclingTemplate?
    var parent: SDCyclingSegment?

    @Relationship(deleteRule: .cascade, inverse: \SDCyclingSegment.parent)
    var children: [SDCyclingSegment]

    init(
        sortOrder: Int,
        kind: String,
        name: String,
        notes: String? = nil,
        durationSeconds: Int? = nil,
        targetType: String? = nil,
        targetMin: Int? = nil,
        targetMax: Int? = nil,
        targetZoneLabel: String? = nil,
        repeats: Int? = nil
    ) {
        self.sortOrder = sortOrder
        self.kind = kind
        self.name = name
        self.notes = notes
        self.durationSeconds = durationSeconds
        self.targetType = targetType
        self.targetMin = targetMin
        self.targetMax = targetMax
        self.targetZoneLabel = targetZoneLabel
        self.repeats = repeats
        self.children = []
    }
}
