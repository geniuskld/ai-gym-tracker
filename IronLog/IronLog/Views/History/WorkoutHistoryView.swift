import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt != nil },
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var workouts: [SDWorkout]
    @Environment(\.modelContext) private var modelContext
    @State private var syncingIds: Set<String> = []

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
                                WorkoutRow(
                                    workout: workout,
                                    isSyncing: syncingIds.contains(workout.workoutId)
                                )
                            }
                            .swipeActions(edge: .leading) {
                                if workout.syncedAt == nil,
                                   SyncService.isAuthenticated,
                                   !syncingIds.contains(workout.workoutId) {
                                    Button {
                                        syncWorkout(workout)
                                    } label: {
                                        Label("Sync", systemImage: "arrow.up.icloud")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        .onDelete(perform: deleteWorkouts)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func syncWorkout(_ workout: SDWorkout) {
        let id = workout.workoutId
        syncingIds.insert(id)
        Task {
            do {
                try await SyncService.uploadWorkout(workout)
                workout.syncedAt = .now
                try? modelContext.save()
            } catch {
                // sync failed -- icon stays as icloud.slash
            }
            syncingIds.remove(id)
        }
    }

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            let workout = workouts[index]
            let workoutId = workout.workoutId
            let wasSynced = workout.syncedAt != nil
            modelContext.delete(workout)

            if wasSynced, SyncService.isConfigured, SyncService.isAuthenticated {
                Task.detached {
                    try? await SyncService.deleteWorkout(workoutId)
                }
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Workout Row

private struct WorkoutRow: View {
    let workout: SDWorkout
    var isSyncing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.templateName)
                        .font(.headline)
                    if let plan = workout.planName {
                        HStack(spacing: 4) {
                            Text(plan)
                            if let v = workout.planVersion {
                                Text("v\(v)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                } else if workout.syncedAt != nil {
                    Image(systemName: "checkmark.icloud")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if SyncService.isAuthenticated {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
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
