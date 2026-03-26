import SwiftUI
import SwiftData

struct TemplatePicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SDPlan.importedAt, order: .reverse) private var plans: [SDPlan]
    @State private var vm = ActiveWorkoutViewModel()
    @State private var showWorkout = false

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
                        ForEach(plans) { plan in
                            Section(plan.planName) {
                                let templates = plan.templates.sorted {
                                    $0.sortOrder < $1.sortOrder
                                }
                                ForEach(templates) { template in
                                    TemplateRow(template: template) {
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
