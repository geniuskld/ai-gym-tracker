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
    @State private var vm = ActiveWorkoutViewModel()
    @State private var navPath = NavigationPath()
    @State private var didAutoResume = false
    @State private var updateBanner: PlanUpdateBanner?
    var autoResumeWorkout: Bool = false

    private var activeWorkout: SDWorkout? { activeWorkouts.first }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if plans.isEmpty {
                    ContentUnavailableView(
                        "No Plans",
                        systemImage: "dumbbell",
                        description: Text("Import a plan first in the Plans tab")
                    )
                } else {
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

                        ForEach(plans) { plan in
                            Section(plan.planName) {
                                let templates = plan.templates.sorted {
                                    $0.sortOrder < $1.sortOrder
                                }
                                ForEach(templates) { template in
                                    TemplateRow(template: template) {
                                        // Discard any stale active workout
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
                }
            }
            .navigationTitle("Start Workout")
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
                let local = plans.first {
                    $0.planId == remote.planId && $0.planType == remote.planType
                }
                let localVersion = local?.planVersion ?? 0

                if remote.planVersion > localVersion {
                    let supported = SchemaRegistry.isSupported(
                        type: remote.planType,
                        version: remote.schemaVersion
                    )
                    await MainActor.run {
                        updateBanner = PlanUpdateBanner(
                            plan: remote,
                            isSchemaSupported: supported
                        )
                    }
                }
            } catch {
                // silently ignore -- not critical
            }
        }
    }

    private func applyUpdate(_ banner: PlanUpdateBanner) {
        guard banner.isSchemaSupported else { return }
        Task {
            do {
                _ = try PlanImportService.importPlan(
                    banner.plan,
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
    let plan: WorkoutPlanJSON
    let isSchemaSupported: Bool
}

private struct PlanUpdateRow: View {
    let banner: PlanUpdateBanner
    let onUpdate: () -> Void

    var body: some View {
        if banner.isSchemaSupported {
            Button(action: onUpdate) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "New plan v\(banner.plan.planVersion) available",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.blue)

                        Text(banner.plan.planName)
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
                        "Update app for plan v\(banner.plan.planVersion)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)

                    Text("Schema \(banner.plan.planType):\(banner.plan.schemaVersion) not supported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}
