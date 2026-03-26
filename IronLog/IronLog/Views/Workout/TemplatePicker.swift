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
    @State private var showWorkout = false

    private var activeWorkout: SDWorkout? { activeWorkouts.first }

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    ContentUnavailableView(
                        "No Plans",
                        systemImage: "dumbbell",
                        description: Text("Import a plan first in the Plans tab")
                    )
                } else {
                    List {
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
                                        showWorkout = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start Workout")
            .navigationDestination(isPresented: $showWorkout) {
                ActiveWorkoutView(vm: vm)
            }
        }
    }

    private func resumeWorkout(_ workout: SDWorkout) {
        // Find the template for this workout
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
        showWorkout = true
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
