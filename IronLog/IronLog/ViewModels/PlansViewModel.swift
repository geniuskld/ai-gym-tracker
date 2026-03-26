import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PlansViewModel {

    enum State {
        case idle
        case parsed(WorkoutPlanJSON)
        case error(String)
    }

    var state: State = .idle
    var showImportSheet = false
    var showPreview = false

    // MARK: - Parse

    func parseFromClipboard() {
        guard let string = UIPasteboard.general.string, !string.isEmpty else {
            state = .error("Clipboard is empty")
            return
        }
        parseJSON(string)
    }

    func parseFromFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            state = .error("Cannot access file")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let plan = try PlanImportService.parse(data)
            state = .parsed(plan)
            showImportSheet = false
            showPreview = true
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func parseJSON(_ string: String) {
        do {
            let plan = try PlanImportService.parse(string)
            state = .parsed(plan)
            showImportSheet = false
            showPreview = true
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Import

    func confirmImport(
        context: ModelContext,
        replace: Bool = false
    ) -> Bool {
        guard case .parsed(let json) = state else { return false }
        do {
            _ = try PlanImportService.importPlan(
                json,
                into: context,
                replaceExisting: replace
            )
            state = .idle
            showPreview = false
            return true
        } catch PlanImportError.duplicatePlan {
            return false
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    // MARK: - Delete

    func deletePlan(_ plan: SDPlan, context: ModelContext) {
        context.delete(plan)
    }

    // MARK: - Helpers

    var parsedPlan: WorkoutPlanJSON? {
        if case .parsed(let plan) = state { return plan }
        return nil
    }

    var errorMessage: String? {
        if case .error(let msg) = state { return msg }
        return nil
    }
}
