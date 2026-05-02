import Foundation
import SwiftData

@Model
final class SDCyclingSegmentLog {
    /// Path within the expanded workout, e.g. "warmup", "block[1].rep[2].work".
    /// Stable across workout sessions for the same template.
    var segmentPath: String
    var sortOrder: Int
    var kind: String
    var name: String

    var durationSecondsActual: Int
    var targetMinBpm: Int?
    var targetMaxBpm: Int?

    var averageHr: Int?
    var maxHr: Int?
    var inZoneSeconds: Int?
    var skipped: Bool = false

    var workout: SDCyclingWorkout?

    init(
        segmentPath: String,
        sortOrder: Int,
        kind: String,
        name: String,
        durationSecondsActual: Int,
        targetMinBpm: Int? = nil,
        targetMaxBpm: Int? = nil,
        averageHr: Int? = nil,
        maxHr: Int? = nil,
        inZoneSeconds: Int? = nil,
        skipped: Bool = false
    ) {
        self.segmentPath = segmentPath
        self.sortOrder = sortOrder
        self.kind = kind
        self.name = name
        self.durationSecondsActual = durationSecondsActual
        self.targetMinBpm = targetMinBpm
        self.targetMaxBpm = targetMaxBpm
        self.averageHr = averageHr
        self.maxHr = maxHr
        self.inZoneSeconds = inZoneSeconds
        self.skipped = skipped
    }

    var inZonePct: Int? {
        guard let inZ = inZoneSeconds, durationSecondsActual > 0 else { return nil }
        return Int((Double(inZ) / Double(durationSecondsActual) * 100).rounded())
    }
}
