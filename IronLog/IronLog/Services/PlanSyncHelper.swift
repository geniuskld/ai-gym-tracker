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
            let summaries = try await SyncService.fetchPlans()
            for summary in summaries {
                importIfNewer(summary, context: context)
            }
            lastSyncDate = .now
        } catch {
            // silent -- auto-sync should not bother the user
        }
    }

    /// Import a plan if the local copy is missing or has a lower version.
    /// Dispatches by `plan_type`; unknown types are skipped silently
    /// (the user will see the plan via the server's web UI / next app update).
    @MainActor
    private static func importIfNewer(
        _ summary: SyncService.PlanSummary,
        context: ModelContext
    ) {
        switch summary.planType {
        case PlanType.strength.rawValue:
            importIfNewerStrength(summary, context: context)
        case PlanType.cycling.rawValue:
            importIfNewerCycling(summary, context: context)
        default:
            // unknown plan type -- skip
            break
        }
    }

    @MainActor
    private static func importIfNewerStrength(
        _ summary: SyncService.PlanSummary,
        context: ModelContext
    ) {
        let planId = summary.planId
        let descriptor = FetchDescriptor<SDPlan>(
            predicate: #Predicate { $0.planId == planId }
        )
        let existing = try? context.fetch(descriptor).first
        if let existing, existing.planVersion >= summary.planVersion {
            return
        }
        do {
            guard case .strength(let json) = try PlanImportService.parse(summary.rawJSON) else {
                return
            }
            _ = try PlanImportService.importStrength(
                json,
                into: context,
                replaceExisting: true
            )
        } catch {
            // skip on failure
        }
    }

    @MainActor
    private static func importIfNewerCycling(
        _ summary: SyncService.PlanSummary,
        context: ModelContext
    ) {
        let planId = summary.planId
        let descriptor = FetchDescriptor<SDCyclingPlan>(
            predicate: #Predicate { $0.planId == planId }
        )
        let existing = try? context.fetch(descriptor).first
        if let existing, existing.planVersion >= summary.planVersion {
            return
        }
        do {
            guard case .cycling(let json) = try PlanImportService.parse(summary.rawJSON) else {
                return
            }
            _ = try PlanImportService.importCycling(
                json,
                into: context,
                replaceExisting: true
            )
        } catch {
            // skip on failure
        }
    }
}
