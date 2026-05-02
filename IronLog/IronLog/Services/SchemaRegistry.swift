import Foundation

enum PlanType: String, Codable, CaseIterable {
    case strength
    case cycling
}

enum PlanSchema {
    /// Schema timestamp the app supports for `strength` plans.
    /// 2026-04-29: weight_kg switched from integer to number (fractional).
    /// 2026-04-30: optional `catalog_id` field on exercises (server-side
    ///             only; iOS ignores -- plans still decode cleanly).
    static let strengthId = "2026-04-30T00:00:00Z"
    /// Schema timestamp the app supports for `cycling` plans.
    static let cyclingId = "2026-04-27T00:00:00Z"

    /// Backwards compat: old code expected a single `id` (strength only).
    static let id = strengthId

    static func id(for type: PlanType) -> String {
        switch type {
        case .strength: return strengthId
        case .cycling:  return cyclingId
        }
    }
}
