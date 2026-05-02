import SwiftUI

struct PlanPreviewView: View {
    @Bindable var vm: PlansViewModel
    @Environment(\.modelContext) private var context
    @State private var showReplaceAlert = false

    let parsed: ParsedPlan

    var body: some View {
        Group {
            switch parsed {
            case .strength(let plan):
                StrengthPreview(plan: plan)
            case .cycling(let plan):
                CyclingPreview(plan: plan)
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

// MARK: - Strength preview

private struct StrengthPreview: View {
    let plan: WorkoutPlanJSON

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: plan.planName)
                LabeledContent("Type", value: "strength")
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
    }
}

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

// MARK: - Cycling preview

private struct CyclingPreview: View {
    let plan: CyclingPlanJSON

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: plan.planName)
                LabeledContent("Type", value: "cycling")
                LabeledContent("Version", value: "v\(plan.planVersion)")
                if let author = plan.author {
                    LabeledContent("Author", value: author)
                }
                LabeledContent("Workouts", value: "\(plan.templates.count)")
                if let mhr = plan.maxHrBpm {
                    LabeledContent("Max HR", value: "\(mhr) bpm")
                }
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
                    if let eq = template.equipment {
                        Label(eq.rawValue.replacingOccurrences(of: "_", with: " "),
                              systemImage: "bicycle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = template.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(
                        Array(template.segments.enumerated()),
                        id: \.offset
                    ) { _, seg in
                        CyclingSegmentPreviewRow(segment: seg)
                    }
                    if let prog = template.progression, let when = prog.advanceWhen {
                        Label(when, systemImage: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct CyclingSegmentPreviewRow: View {
    let segment: CyclingSegmentJSON

    var body: some View {
        if segment.kind == .intervalBlock, let children = segment.children, let reps = segment.repeats {
            DisclosureGroup {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    leafRow(child)
                }
            } label: {
                HStack {
                    Image(systemName: "repeat")
                    Text("\(segment.name) -- \(reps)x")
                        .font(.subheadline.weight(.medium))
                }
            }
        } else {
            leafRow(segment)
        }
    }

    @ViewBuilder
    private func leafRow(_ s: CyclingSegmentJSON) -> some View {
        HStack {
            Image(systemName: icon(for: s.kind))
                .foregroundStyle(color(for: s.kind))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.subheadline)
                HStack(spacing: 8) {
                    if let dur = s.durationSeconds {
                        Text(formatDuration(dur))
                    }
                    if let target = s.target {
                        Text(formatTarget(target))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for kind: CyclingSegmentKind) -> String {
        switch kind {
        case .warmup: return "thermometer.sun"
        case .work: return "flame"
        case .recovery: return "leaf"
        case .cooldown: return "snowflake"
        case .steady: return "equal"
        case .intervalBlock: return "repeat"
        }
    }

    private func color(for kind: CyclingSegmentKind) -> Color {
        switch kind {
        case .warmup: return .orange
        case .work: return .red
        case .recovery: return .green
        case .cooldown: return .blue
        case .steady: return .purple
        case .intervalBlock: return .secondary
        }
    }

    private func formatDuration(_ s: Int) -> String {
        s >= 60 ? "\(s / 60):\(String(format: "%02d", s % 60))" : "\(s)s"
    }

    private func formatTarget(_ t: CyclingTargetJSON) -> String {
        switch t.type {
        case .hrBpmRange:
            let label = t.zoneLabel.map { " (\($0))" } ?? ""
            return "\(t.min ?? 0)-\(t.max ?? 0) bpm\(label)"
        case .rpe:
            return "RPE \(t.min ?? 0)-\(t.max ?? 0)"
        case .free:
            return "free"
        }
    }
}
