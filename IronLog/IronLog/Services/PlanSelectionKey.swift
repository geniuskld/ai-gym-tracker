import Foundation

enum PlanSelectionKey {
    static let storageKey = "selectedPlanKey"
    static let legacyStorageKey = "selectedPlanId"

    static func make(type: PlanType, planId: String) -> String {
        "\(type.rawValue):\(planId)"
    }

    static func matches(
        selection: String,
        legacyPlanId: String,
        type: PlanType,
        planId: String
    ) -> Bool {
        if selection == make(type: type, planId: planId) {
            return true
        }
        return selection.isEmpty && legacyPlanId == planId
    }
}
