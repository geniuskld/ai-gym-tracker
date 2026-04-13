import Foundation
import SwiftData

enum PlanSyncHelper {

    private static let throttleInterval: TimeInterval = 600 // 10 min
    private(set) static var lastSyncDate: Date?

    /// Sync if enough time has passed since the last auto-sync.
    /// Pull-to-refresh calls bypass throttle by passing `force: true`.
    @MainActor
    static func syncIfNeeded(
        context: ModelContext,
        force: Bool = false
    ) async {
        guard SyncService.isConfigured, SyncService.isAuthenticated else { return }
        if !force,
           let last = lastSyncDate,
           Date.now.timeIntervalSince(last) < throttleInterval {
            return
        }
        await sync(context: context)
    }

    @MainActor
    static func sync(context: ModelContext) async {
        guard SyncService.isConfigured, SyncService.isAuthenticated else { return }
        do {
            let json = try await SyncService.fetchPlan()
            let descriptor = FetchDescriptor<SDPlan>(
                predicate: #Predicate {
                    $0.planId == json.planId
                }
            )
            let existing = try? context.fetch(descriptor).first
            if let existing, existing.planVersion >= json.planVersion {
                lastSyncDate = .now
                return
            }
            _ = try PlanImportService.importPlan(
                json,
                into: context,
                replaceExisting: true
            )
            lastSyncDate = .now
        } catch {
            // silent -- auto-sync should not bother the user
        }
    }
}
