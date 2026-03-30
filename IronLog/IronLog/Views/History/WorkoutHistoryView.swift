import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt != nil },
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var workouts: [SDWorkout]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Completed workouts will appear here")
                    )
                } else {
                    List {
                        ForEach(workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutRow(workout: workout)
                            }
                        }
                        .onDelete(perform: deleteWorkouts)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(workouts[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Workout Row

private struct WorkoutRow: View {
    let workout: SDWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.templateName)
                        .font(.headline)
                    if let plan = workout.planName {
                        Text(plan)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let effort = workout.perceivedEffort {
                    effortBadge(effort)
                }
            }

            HStack(spacing: 12) {
                Label(formattedDate, systemImage: "calendar")
                if let dur = workout.durationMinutes {
                    Label("\(Int(dur)) min", systemImage: "clock")
                }
                Label(
                    "\(workout.exercises.count) exercises",
                    systemImage: "list.number"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        workout.startedAt.formatted(
            .dateTime.day().month(.abbreviated).hour().minute()
        )
    }

    @ViewBuilder
    private func effortBadge(_ effort: Int) -> some View {
        let (label, color): (String, Color) = switch effort {
        case 1: ("Easy", .green)
        case 2: ("Moderate", .orange)
        case 3: ("Hard", .red)
        default: ("?", .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Workout Detail

struct WorkoutDetailView: View {
    let workout: SDWorkout
    @State private var showShareSheet = false

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent(
                    "Date",
                    value: workout.startedAt.formatted(
                        .dateTime.day().month(.abbreviated).year().hour().minute()
                    )
                )
                if let dur = workout.durationMinutes {
                    LabeledContent("Duration", value: "\(Int(dur)) min")
                }
                if let effort = workout.perceivedEffort {
                    let label = switch effort {
                    case 1: "Easy"
                    case 2: "Moderate"
                    case 3: "Hard"
                    default: "?"
                    }
                    LabeledContent("Effort", value: label)
                }
            }

            let sortedExercises = workout.exercises.sorted { $0.order < $1.order }
            ForEach(sortedExercises) { exLog in
                Section(exLog.exerciseName) {
                    let sortedSets = exLog.sets.sorted { $0.setNumber < $1.setNumber }
                    ForEach(sortedSets) { setLog in
                        HStack {
                            Text("Set \(setLog.setNumber)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)

                            if setLog.setType != "working" {
                                Text(setLog.setType)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            if let w = setLog.weightKg {
                                Text("\(Int(w)) kg")
                                    .font(.subheadline.weight(.medium))
                            }

                            if let r = setLog.reps {
                                Text("\(r) reps")
                                    .font(.subheadline)
                            }

                            if setLog.failed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.templateName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: WorkoutExportService.exportJSON(workout),
                    preview: SharePreview(
                        "\(workout.templateName).json",
                        image: Image(systemName: "doc.text")
                    )
                )
            }
        }
    }
}
