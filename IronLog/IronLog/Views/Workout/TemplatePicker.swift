import SwiftUI
import SwiftData

/// A unified handle to a plan that can drive the picker UI.
/// Backed by either a strength or cycling SwiftData plan.
private enum AnyPlanHandle: Identifiable, Hashable {
    case strength(SDPlan)
    case cycling(SDCyclingPlan)

    var id: String {
        switch self {
        case .strength(let p): return "s:\(p.persistentModelID.hashValue)"
        case .cycling(let p):  return "c:\(p.persistentModelID.hashValue)"
        }
    }

    var planId: String {
        switch self {
        case .strength(let p): return p.planId
        case .cycling(let p):  return p.planId
        }
    }

    var planType: PlanType {
        switch self {
        case .strength: return .strength
        case .cycling:  return .cycling
        }
    }

    var selectionKey: String {
        PlanSelectionKey.make(type: planType, planId: planId)
    }

    var planName: String {
        switch self {
        case .strength(let p): return p.planName
        case .cycling(let p):  return p.planName
        }
    }

    var schema: String {
        switch self {
        case .strength(let p): return p.schema
        case .cycling(let p):  return p.schema
        }
    }

    var isSupported: Bool {
        switch self {
        case .strength(let p): return p.isSupported
        case .cycling(let p):  return p.isSupported
        }
    }

    var isCycling: Bool {
        if case .cycling = self { return true }
        return false
    }
}

struct TemplatePicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var strengthPlans: [SDPlan]
    @Query(sort: \SDCyclingPlan.importedAt, order: .reverse) private var cyclingPlans: [SDCyclingPlan]
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt == nil },
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var activeWorkouts: [SDWorkout]
    @Query(
        filter: #Predicate<SDCyclingWorkout> { $0.finishedAt == nil },
        sort: \SDCyclingWorkout.startedAt,
        order: .reverse
    ) private var activeCyclingWorkouts: [SDCyclingWorkout]
    @Query(
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var allWorkouts: [SDWorkout]
    @Query(
        sort: \SDCyclingWorkout.startedAt,
        order: .reverse
    ) private var allCyclingWorkouts: [SDCyclingWorkout]
    @State private var vm = ActiveWorkoutViewModel()
    @State private var cyclingVM = CyclingWorkoutViewModel()
    @State private var navPath = NavigationPath()
    @State private var didAutoResume = false
    @State private var pendingWorkoutStart: PendingWorkoutStart?
    @State private var showStartConfirmation = false
    @State private var recoveryMessage: String?
    @AppStorage(PlanSelectionKey.storageKey) private var selectedPlanKey: String = ""
    @AppStorage(PlanSelectionKey.legacyStorageKey) private var legacySelectedPlanId: String = ""
    var autoResumeWorkout: Bool = false

    private var activeStrengthWorkouts: [SDWorkout] {
        activeWorkouts.filter { $0.finishedAt == nil }
    }
    private var activeCyclingWorkoutEntries: [SDCyclingWorkout] {
        activeCyclingWorkouts.filter { $0.finishedAt == nil }
    }
    private var activeWorkout: SDWorkout? {
        activeStrengthWorkouts.first
    }
    private var activeCyclingWorkout: SDCyclingWorkout? {
        activeCyclingWorkoutEntries.first
    }
    private var hasActiveWorkout: Bool {
        activeWorkout != nil || activeCyclingWorkout != nil
    }

    private var allPlans: [AnyPlanHandle] {
        strengthPlans.map(AnyPlanHandle.strength) + cyclingPlans.map(AnyPlanHandle.cycling)
    }

    private var supportedPlans: [AnyPlanHandle] {
        allPlans.filter(\.isSupported)
    }

    private var unsupportedPlans: [AnyPlanHandle] {
        allPlans.filter { !$0.isSupported }
    }

    private var currentPlan: AnyPlanHandle? {
        // 1. Saved selection
        if !selectedPlanKey.isEmpty,
           let plan = supportedPlans.first(where: { $0.selectionKey == selectedPlanKey }) {
            return plan
        }
        if selectedPlanKey.isEmpty,
           !legacySelectedPlanId.isEmpty,
           let plan = supportedPlans.first(where: { $0.planId == legacySelectedPlanId }) {
            return plan
        }
        // 2. Last used (strength or cycling)
        if let last = lastUsedPlan,
           let plan = supportedPlans.first(where: {
               $0.planType == last.type && $0.planId == last.planId
           }) {
            return plan
        }
        // 3. First available
        return supportedPlans.first
    }

    private var lastUsedPlan: (type: PlanType, planId: String, startedAt: Date)? {
        let strength = allWorkouts
            .compactMap { workout -> (PlanType, String, Date)? in
                guard let planId = workout.planId else { return nil }
                return (.strength, planId, workout.startedAt)
            }
            .first
        let cycling = allCyclingWorkouts
            .compactMap { workout -> (PlanType, String, Date)? in
                guard let planId = workout.planId else { return nil }
                return (.cycling, planId, workout.startedAt)
            }
            .first

        switch (strength, cycling) {
        case (.some(let s), .some(let c)):
            return s.2 >= c.2
                ? (s.0, s.1, s.2)
                : (c.0, c.1, c.2)
        case (.some(let s), .none):
            return (s.0, s.1, s.2)
        case (.none, .some(let c)):
            return (c.0, c.1, c.2)
        case (.none, .none):
            return nil
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if allPlans.isEmpty {
                    ContentUnavailableView(
                        "No Plans",
                        systemImage: "dumbbell",
                        description: Text("Import a plan first in the Plans tab")
                    )
                } else if supportedPlans.isEmpty {
                    let planDates = unsupportedPlans
                        .map(\.schema)
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    ContentUnavailableView(
                        "Plans Outdated",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Schema not supported. Sync or re-import.\nPlan: \(planDates.isEmpty ? "unknown" : planDates), app: \(PlanSchema.id)")
                    )
                } else if let plan = currentPlan {
                    planList(plan)
                }
            }
            .navigationTitle(currentPlan?.planName ?? "Start Workout")
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .strength:
                    ActiveWorkoutView(vm: vm)
                case .cycling:
                    CyclingWorkoutView(vm: cyclingVM)
                }
            }
            .onAppear {
                migrateLegacySelectionIfNeeded()
                if !didAutoResume {
                    // Cycling resume takes priority -- it's the case where
                    // the Live Activity sent the user back here. Strength
                    // is the legacy path with the same flag.
                    if let activeCycling = activeCyclingWorkout {
                        didAutoResume = true
                        resumeCyclingWorkout(activeCycling)
                    } else if autoResumeWorkout, let active = activeWorkout {
                        didAutoResume = true
                        resumeStrengthWorkout(active)
                    }
                }
                checkForPlanUpdate()
            }
            .confirmationDialog(
                "Workout in progress",
                isPresented: $showStartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Resume Current Workout") {
                    resumeCurrentWorkout()
                    pendingWorkoutStart = nil
                }
                Button("Discard and Start New", role: .destructive) {
                    if let pendingWorkoutStart {
                        startPendingWorkout(pendingWorkoutStart, replacingActive: true)
                    }
                    pendingWorkoutStart = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingWorkoutStart = nil
                }
            } message: {
                Text(activeWorkoutMessage)
            }
            .alert(
                "Workout Updated",
                isPresented: Binding(
                    get: { recoveryMessage != nil },
                    set: { if !$0 { recoveryMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    recoveryMessage = nil
                }
            } message: {
                Text(recoveryMessage ?? "")
            }
        }
    }

    private enum WorkoutRoute: Hashable { case strength, cycling }

    private enum PendingWorkoutStart {
        case strength(SDTemplate)
        case cycling(SDCyclingPlan, SDCyclingTemplate)
    }

    @ViewBuilder
    private func planList(_ plan: AnyPlanHandle) -> some View {
        switch plan {
        case .strength(let sd):
            List {
                activeWorkoutSections
                let templates = sd.templates.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(templates) { template in
                    TemplateRow(template: template) {
                        requestStartStrength(template)
                    }
                }
            }
        case .cycling(let sd):
            List {
                activeWorkoutSections
                let templates = sd.templates.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(templates) { template in
                    CyclingTemplateRow(template: template) {
                        requestStartCycling(plan: sd, template: template)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeWorkoutSections: some View {
        if hasActiveWorkout {
            Section("In Progress") {
                ForEach(activeStrengthWorkouts) { active in
                    ResumeRow(
                        title: "Strength in progress",
                        detail: activeWorkoutDetail(
                            name: active.templateName,
                            startedAt: active.startedAt
                        ),
                        systemImage: "figure.strengthtraining.traditional",
                        tint: .orange
                    ) {
                        resumeStrengthWorkout(active)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            discardStrengthWorkout(active)
                        } label: {
                            Label("Discard", systemImage: "trash")
                        }
                        Button {
                            closeStrengthWorkout(active)
                        } label: {
                            Label("Close", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
                ForEach(activeCyclingWorkoutEntries) { active in
                    ResumeRow(
                        title: "Cycling in progress",
                        detail: activeWorkoutDetail(
                            name: active.templateName,
                            startedAt: active.startedAt
                        ),
                        systemImage: "bicycle",
                        tint: .blue
                    ) {
                        resumeCyclingWorkout(active)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            discardCyclingWorkout(active)
                        } label: {
                            Label("Discard", systemImage: "trash")
                        }
                        Button {
                            closeCyclingWorkout(active)
                        } label: {
                            Label("Close", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
            }
        }
    }

    private func activeWorkoutDetail(name: String, startedAt: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(name) - \(formatter.localizedString(for: startedAt, relativeTo: .now))"
    }

    private var activeWorkoutMessage: String {
        if let activeCyclingWorkout {
            return "Resume \(activeCyclingWorkout.templateName), or discard it before starting another workout."
        }
        if let activeWorkout {
            return "Resume \(activeWorkout.templateName), or discard it before starting another workout."
        }
        return "Resume the current workout, or discard it before starting another workout."
    }

    private func checkForPlanUpdate() {
        Task {
            await PlanSyncHelper.syncIfNeeded(context: context)
        }
    }

    private func migrateLegacySelectionIfNeeded() {
        guard selectedPlanKey.isEmpty, !legacySelectedPlanId.isEmpty else {
            return
        }
        if let plan = supportedPlans.first(where: { $0.planId == legacySelectedPlanId }) {
            selectedPlanKey = plan.selectionKey
        }
    }

    private func resumeStrengthWorkout(_ workout: SDWorkout) {
        let templateId = workout.templateId
        let template = strengthPlans.flatMap(\.templates).first {
            $0.templateId == templateId
        }
        guard let template else {
            closeStrengthWorkout(
                workout,
                message: "This workout's plan is no longer available, so I closed the stale in-progress entry."
            )
            return
        }

        navPath = NavigationPath()
        vm.resumeWorkout(
            sdWorkout: workout,
            template: template,
            context: context
        )
        navPath.append(WorkoutRoute.strength)
    }

    private func resumeCyclingWorkout(_ workout: SDCyclingWorkout) {
        let templateId = workout.templateId
        // Find the matching plan + template
        var resolvedPlan: SDCyclingPlan?
        var resolvedTemplate: SDCyclingTemplate?
        for plan in cyclingPlans {
            if let t = plan.templates.first(where: { $0.templateId == templateId }) {
                resolvedPlan = plan
                resolvedTemplate = t
                break
            }
        }
        guard let plan = resolvedPlan, let template = resolvedTemplate else {
            closeCyclingWorkout(
                workout,
                message: "This cycling workout's plan is no longer available, so I closed the stale in-progress entry."
            )
            return
        }

        navPath = NavigationPath()
        cyclingVM.resumeWorkout(
            plan: plan,
            template: template,
            sdWorkout: workout,
            context: context
        )
        navPath.append(WorkoutRoute.cycling)
    }

    private func resumeCurrentWorkout() {
        if let activeCyclingWorkout {
            resumeCyclingWorkout(activeCyclingWorkout)
        } else if let activeWorkout {
            resumeStrengthWorkout(activeWorkout)
        }
    }

    private func closeStrengthWorkout(
        _ workout: SDWorkout,
        message: String = "Workout closed."
    ) {
        let finishedAt = Date.now
        workout.finishedAt = finishedAt
        if workout.durationMinutes == nil {
            workout.durationMinutes = finishedAt.timeIntervalSince(workout.startedAt) / 60
        }
        saveRecoveryChange(successMessage: message)
    }

    private func closeCyclingWorkout(
        _ workout: SDCyclingWorkout,
        message: String = "Cycling workout closed."
    ) {
        let finishedAt = Date.now
        workout.finishedAt = finishedAt
        if workout.totalDurationSeconds == 0 {
            workout.totalDurationSeconds = max(
                0,
                Int(finishedAt.timeIntervalSince(workout.startedAt))
            )
        }
        saveRecoveryChange(successMessage: message)
    }

    private func discardStrengthWorkout(_ workout: SDWorkout) {
        context.delete(workout)
        saveRecoveryChange(successMessage: "Workout discarded.")
    }

    private func discardCyclingWorkout(_ workout: SDCyclingWorkout) {
        context.delete(workout)
        saveRecoveryChange(successMessage: "Cycling workout discarded.")
    }

    private func saveRecoveryChange(successMessage: String) {
        do {
            try context.save()
            recoveryMessage = successMessage
        } catch {
            recoveryMessage = "Could not update workout: \(error.localizedDescription)"
        }
    }

    private func requestStartStrength(_ template: SDTemplate) {
        if hasActiveWorkout {
            pendingWorkoutStart = .strength(template)
            showStartConfirmation = true
        } else {
            startStrengthWorkout(template, replacingActive: false)
        }
    }

    private func requestStartCycling(
        plan: SDCyclingPlan,
        template: SDCyclingTemplate
    ) {
        if hasActiveWorkout {
            pendingWorkoutStart = .cycling(plan, template)
            showStartConfirmation = true
        } else {
            startCyclingWorkout(
                plan: plan,
                template: template,
                replacingActive: false
            )
        }
    }

    private func startPendingWorkout(
        _ pending: PendingWorkoutStart,
        replacingActive: Bool
    ) {
        switch pending {
        case .strength(let template):
            startStrengthWorkout(template, replacingActive: replacingActive)
        case .cycling(let plan, let template):
            startCyclingWorkout(
                plan: plan,
                template: template,
                replacingActive: replacingActive
            )
        }
    }

    private func startStrengthWorkout(
        _ template: SDTemplate,
        replacingActive: Bool
    ) {
        if replacingActive {
            discardActiveWorkouts()
        }
        vm.startWorkout(template: template, context: context)
        navPath.append(WorkoutRoute.strength)
    }

    private func startCyclingWorkout(
        plan: SDCyclingPlan,
        template: SDCyclingTemplate,
        replacingActive: Bool
    ) {
        if replacingActive {
            discardActiveWorkouts()
        }
        cyclingVM.startWorkout(plan: plan, template: template, context: context)
        navPath.append(WorkoutRoute.cycling)
    }

    private func discardActiveWorkouts() {
        vm.reset()
        cyclingVM.reset()
        if let activeWorkout {
            context.delete(activeWorkout)
        }
        if let activeCyclingWorkout {
            context.delete(activeCyclingWorkout)
        }
    }
}

// MARK: - Resume Row

private struct ResumeRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        title,
                        systemImage: systemImage
                    )
                    .font(.headline)
                    .foregroundStyle(tint)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Resume")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Strength Template Row

private struct TemplateRow: View {
    let template: SDTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)

                let groups = template.groups.sorted { $0.sortOrder < $1.sortOrder }
                let exerciseCount = groups.reduce(0) { $0 + $1.exercises.count }

                HStack(spacing: 12) {
                    Label(
                        "\(exerciseCount) exercises",
                        systemImage: "figure.strengthtraining.traditional"
                    )

                    let groupNames = groups.map(\.name).joined(separator: " / ")
                    Text(groupNames)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Cycling Template Row

private struct CyclingTemplateRow: View {
    let template: SDCyclingTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.headline)

                let totalSec = CyclingExpander.totalDuration(for: template)
                let stepCount = CyclingExpander.expand(template).count

                HStack(spacing: 12) {
                    Label(
                        formatMinutes(totalSec),
                        systemImage: "clock"
                    )
                    Label(
                        "\(stepCount) steps",
                        systemImage: "list.number"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
    }
}
