import SwiftUI

struct PlanPreviewView: View {
    @Bindable var vm: PlansViewModel
    @Environment(\.modelContext) private var context
    @State private var showReplaceAlert = false

    let plan: WorkoutPlanJSON

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: plan.planName)
                LabeledContent("Version", value: "v\(plan.planVersion)")
                if let author = plan.author {
                    LabeledContent("Author", value: author)
                }
                LabeledContent("Templates", value: "\(plan.templates.count)")
                if let notes = plan.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(
                Array(plan.templates.enumerated()),
                id: \.element.id
            ) { _, template in
                Section(template.name) {
                    ForEach(
                        Array(template.groups.enumerated()),
                        id: \.offset
                    ) { _, group in
                        DisclosureGroup(group.name) {
                            ForEach(
                                Array(group.exercises.enumerated()),
                                id: \.element.id
                            ) { _, exercise in
                                ExercisePreviewRow(exercise: exercise)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    let success = vm.confirmImport(context: context)
                    if !success {
                        showReplaceAlert = true
                    }
                }
            }
        }
        .alert(
            "Plan Already Exists",
            isPresented: $showReplaceAlert
        ) {
            Button("Replace") {
                _ = vm.confirmImport(
                    context: context,
                    replace: true
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A plan with this name already exists. Replace it?")
        }
    }
}

// MARK: - Exercise Preview Row

private struct ExercisePreviewRow: View {
    let exercise: ExerciseJSON

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(exercise.name)
                    .font(.subheadline)
                Spacer()
                if let technique = exercise.technique, technique != .straight {
                    Text(technique.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                Text("\(exercise.sets.count) sets")
                if let firstSet = exercise.sets.first, let r = firstSet.reps {
                    Text("\(r) reps")
                }
                if let rest = exercise.restSeconds {
                    Text("\(rest)s rest")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
