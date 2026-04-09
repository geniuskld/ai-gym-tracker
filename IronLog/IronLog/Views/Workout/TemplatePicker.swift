import SwiftUI
import SwiftData

struct TemplatePicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var plans: [SDPlan]
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt == nil },
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var activeWorkouts: [SDWorkout]
    @Query(
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var allWorkouts: [SDWorkout]
    @State private var vm = ActiveWorkoutViewModel()
    @State private var navPath = NavigationPath()
    @State private var didAutoResume = false
    @State private var updateBanner: PlanUpdateBanner?
    @AppStorage("selectedPlanId") private var selectedPlanId: String = ""
    var autoResumeWorkout: Bool = false

    private var activeWorkout: SDWorkout? { activeWorkouts.first }

    private var supportedPlans: [SDPlan] {
        plans.filter(\.isSupported)
    }

    private var currentPlan: SDPlan? {
        // 1. Saved selection
        if !selectedPlanId.isEmpty,
           let plan = supportedPlans.first(where: { $0.planId == selectedPlanId }) {
            return plan
        }
        // 2. Last used (from most recent workout)
        if let lastPlanId = allWorkouts.first(where: { $0.planId != nil })?.planId,
           let plan = supportedPlans.first(where: { $0.planId == lastPlanId }) {
            return plan
        }
        // 3. First available
        return supportedPlans.first
    }

    private var unsupportedPlans: [SDPlan] {
        plans.filter { !$0.isSupported }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if plans.isEmpty {
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
                    List {
                        // Plan update banner
                        if let banner = updateBanner {
                            Section {
                                PlanUpdateRow(banner: banner) {
                                    applyUpdate(banner)
                                }
                            }
                        }

                        // Resume banner
                        if let active = activeWorkout {
                            Section {
                                ResumeRow(workout: active) {
                                    resumeWorkout(active)
                                }
                            }
                        }

                        let templates = plan.templates.sorted {
                            $0.sortOrder < $1.sortOrder
                        }
                        ForEach(templates) { template in
                            TemplateRow(template: template) {
                                if let old = activeWorkout {
                                    context.delete(old)
                                }
                                vm.startWorkout(
                                    template: template,
                                    context: context
                                )
                                navPath.append("workout")
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentPlan?.planName ?? "Start Workout")
            .toolbar {
                if plans.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(supportedPlans) { plan in
                                Button {
                                    selectedPlanId = plan.planId
                                } label: {
                                    if plan.planId == currentPlan?.planId {
                                        Label(plan.planName, systemImage: "checkmark")
                                    } else {
                                        Text(plan.planName)
                                    }
                                }
                            }
                            if !unsupportedPlans.isEmpty {
                                Divider()
                                ForEach(unsupportedPlans) { plan in
                                    VStack(alignment: .leading) {
                                        Label(
                                            "\(plan.planName) -- not supported",
                                            systemImage: "exclamationmark.triangle"
                                        )
                                        Text("plan: \(plan.schema), app: \(PlanSchema.id)")
                                            .font(.caption2)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { _ in
                ActiveWorkoutView(vm: vm)
            }
            .onAppear {
                if autoResumeWorkout && !didAutoResume,
                   let active = activeWorkout {
                    didAutoResume = true
                    resumeWorkout(active)
                }
                checkForPlanUpdate()
            }
        }
    }

    private func checkForPlanUpdate() {
        guard SyncService.isConfigured, SyncService.isAuthenticated else { return }
        Task {
            do {
                let remote = try await SyncService.fetchPlan()
                let remotePlanType = remote.planType.rawValue
                let local = plans.first {
                    $0.planId == remote.planId && $0.planType == remotePlanType
                }
                let localVersion = local?.planVersion ?? 0

                if remote.planVersion > localVersion {
                    await MainActor.run {
                        updateBanner = PlanUpdateBanner(plan: remote)
                    }
                }
            } catch is DecodingError {
                await MainActor.run {
                    updateBanner = PlanUpdateBanner(plan: nil)
                }
            } catch {
                // network/auth errors -- silently ignore
            }
        }
    }

    private func applyUpdate(_ banner: PlanUpdateBanner) {
        guard let plan = banner.plan else { return }
        Task {
            do {
                _ = try PlanImportService.importPlan(
                    plan,
                    into: context,
                    replaceExisting: true
                )
                await MainActor.run {
                    updateBanner = nil
                }
            } catch {
                // keep banner visible on failure
            }
        }
    }

    private func resumeWorkout(_ workout: SDWorkout) {
        let templateId = workout.templateId
        let template = plans.flatMap(\.templates).first {
            $0.templateId == templateId
        }
        guard let template else { return }

        vm.resumeWorkout(
            sdWorkout: workout,
            template: template,
            context: context
        )
        navPath.append("workout")
    }
}

// MARK: - Resume Row

private struct ResumeRow: View {
    let workout: SDWorkout
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Workout in progress",
                        systemImage: "figure.run"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)

                    Text("\(workout.templateName) - \(workout.startedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Resume")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Template Row

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

// MARK: - Plan Update Banner

struct PlanUpdateBanner {
    let plan: WorkoutPlanJSON?
}

private struct PlanUpdateRow: View {
    let banner: PlanUpdateBanner
    let onUpdate: () -> Void

    var body: some View {
        if let plan = banner.plan {
            Button(action: onUpdate) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "New plan v\(plan.planVersion) available",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.blue)

                        Text(plan.planName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Update")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 4)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Update app for new plan",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)

                    Text("Plan format not supported by this version")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}
