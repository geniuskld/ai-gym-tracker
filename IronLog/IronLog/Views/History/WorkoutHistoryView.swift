import SwiftUI
import SwiftData

// MARK: - Polymorphic history item

/// Wraps either a strength workout (`SDWorkout`) or a cycling workout
/// (`SDCyclingWorkout`) so the history list can merge both kinds and
/// render them chronologically.
private enum HistoryItem: Identifiable {
    case strength(SDWorkout)
    case cycling(SDCyclingWorkout)

    var id: String {
        switch self {
        case .strength(let w): return "s:\(w.workoutId)"
        case .cycling(let w):  return "c:\(w.workoutId)"
        }
    }

    var startedAt: Date {
        switch self {
        case .strength(let w): return w.startedAt
        case .cycling(let w):  return w.startedAt
        }
    }
}

struct WorkoutHistoryView: View {
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt != nil },
        sort: \SDWorkout.startedAt,
        order: .reverse
    ) private var strengthWorkouts: [SDWorkout]
    @Query(
        filter: #Predicate<SDCyclingWorkout> { $0.finishedAt != nil },
        sort: \SDCyclingWorkout.startedAt,
        order: .reverse
    ) private var cyclingWorkouts: [SDCyclingWorkout]

    @Environment(\.modelContext) private var modelContext
    @State private var syncingIds: Set<String> = []

    private var allItems: [HistoryItem] {
        let s = strengthWorkouts.map(HistoryItem.strength)
        let c = cyclingWorkouts.map(HistoryItem.cycling)
        return (s + c).sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Completed workouts will appear here")
                    )
                } else {
                    List {
                        ForEach(allItems) { item in
                            switch item {
                            case .strength(let w):
                                strengthRow(w)
                            case .cycling(let w):
                                cyclingRow(w)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func strengthRow(_ workout: SDWorkout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            StrengthWorkoutRow(
                workout: workout,
                isSyncing: syncingIds.contains(workout.workoutId)
            )
        }
        .swipeActions(edge: .leading) {
            if workout.syncedAt == nil,
               SyncService.isAuthenticated,
               !syncingIds.contains(workout.workoutId) {
                Button {
                    syncStrength(workout)
                } label: {
                    Label("Sync", systemImage: "arrow.up.icloud")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteStrength(workout)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func cyclingRow(_ workout: SDCyclingWorkout) -> some View {
        NavigationLink {
            CyclingWorkoutDetailView(workout: workout)
        } label: {
            CyclingWorkoutRow(
                workout: workout,
                isSyncing: syncingIds.contains(workout.workoutId)
            )
        }
        .swipeActions(edge: .leading) {
            if workout.syncedAt == nil,
               SyncService.isAuthenticated,
               !syncingIds.contains(workout.workoutId) {
                Button {
                    syncCycling(workout)
                } label: {
                    Label("Sync", systemImage: "arrow.up.icloud")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteCycling(workout)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func syncStrength(_ workout: SDWorkout) {
        let id = workout.workoutId
        syncingIds.insert(id)
        Task {
            _ = await WorkoutSyncService.uploadStrength(
                workout,
                context: modelContext,
                force: true
            )
            syncingIds.remove(id)
        }
    }

    private func syncCycling(_ workout: SDCyclingWorkout) {
        let id = workout.workoutId
        syncingIds.insert(id)
        Task {
            _ = await WorkoutSyncService.uploadCycling(
                workout,
                context: modelContext,
                force: true
            )
            syncingIds.remove(id)
        }
    }

    private func deleteStrength(_ workout: SDWorkout) {
        let workoutId = workout.workoutId
        let wasSynced = workout.syncedAt != nil
        modelContext.delete(workout)
        try? modelContext.save()
        if wasSynced, SyncService.isConfigured, SyncService.isAuthenticated {
            Task.detached {
                try? await SyncService.deleteWorkout(workoutId)
            }
        }
    }

    private func deleteCycling(_ workout: SDCyclingWorkout) {
        let workoutId = workout.workoutId
        let wasSynced = workout.syncedAt != nil
        modelContext.delete(workout)
        try? modelContext.save()
        if wasSynced, SyncService.isConfigured, SyncService.isAuthenticated {
            Task.detached {
                try? await SyncService.deleteWorkout(workoutId)
            }
        }
    }
}

// MARK: - Strength Workout Row

private struct StrengthWorkoutRow: View {
    let workout: SDWorkout
    var isSyncing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(workout.templateName)
                            .font(.headline)
                    }
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
                syncIcon(isSyncing: isSyncing, syncedAt: workout.syncedAt)
                if let effort = workout.perceivedEffort {
                    strengthEffortBadge(effort)
                }
            }

            HStack(spacing: 12) {
                Label(formattedDate(workout.startedAt), systemImage: "calendar")
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
}

// MARK: - Cycling Workout Row

private struct CyclingWorkoutRow: View {
    let workout: SDCyclingWorkout
    var isSyncing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bicycle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(workout.templateName)
                            .font(.headline)
                    }
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
                syncIcon(isSyncing: isSyncing, syncedAt: workout.syncedAt)
                if let effort = workout.perceivedEffort {
                    cyclingEffortBadge(effort)
                }
            }

            HStack(spacing: 12) {
                Label(formattedDate(workout.startedAt), systemImage: "calendar")
                Label(
                    "\(workout.totalDurationSeconds / 60) min",
                    systemImage: "clock"
                )
                if workout.hadHrSource, let avg = workout.averageHr {
                    Label("avg \(avg)", systemImage: "heart")
                }
                Label("\(workout.segments.count) segments", systemImage: "list.number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sync icon helper

@ViewBuilder
private func syncIcon(isSyncing: Bool, syncedAt: Date?) -> some View {
    if isSyncing {
        ProgressView().controlSize(.mini)
    } else if syncedAt != nil {
        Image(systemName: "checkmark.icloud")
            .foregroundStyle(.green)
            .font(.caption)
    } else if SyncService.isAuthenticated {
        Image(systemName: "icloud.slash")
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}

private func formattedDate(_ d: Date) -> String {
    d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
}

// Effort badges -- different scales:
// strength = 1-3 (Easy/Moderate/Hard); cycling = 1-10.

@ViewBuilder
private func strengthEffortBadge(_ effort: Int) -> some View {
    let (label, color): (String, Color) = switch effort {
    case 1: ("Easy", .green)
    case 2: ("Moderate", .orange)
    case 3: ("Hard", .red)
    default: ("?", .gray)
    }
    Text(label)
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
}

@ViewBuilder
private func cyclingEffortBadge(_ effort: Int) -> some View {
    let color: Color = switch effort {
    case 1...3: .green
    case 4...6: .yellow
    case 7...8: .orange
    case 9...10: .red
    default: .gray
    }
    Text("\(effort)/10")
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
}

// MARK: - Strength Detail

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
                                Text("\(formatWeight(w)) kg")
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

// MARK: - Cycling Detail

struct CyclingWorkoutDetailView: View {
    let workout: SDCyclingWorkout

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent(
                    "Date",
                    value: workout.startedAt.formatted(
                        .dateTime.day().month(.abbreviated).year().hour().minute()
                    )
                )
                LabeledContent(
                    "Duration",
                    value: formatDuration(workout.totalDurationSeconds)
                )
                if workout.hadHrSource {
                    if let avg = workout.averageHr {
                        LabeledContent("Average HR", value: "\(avg) bpm")
                    }
                    if let max = workout.maxHr {
                        LabeledContent("Max HR", value: "\(max) bpm")
                    }
                } else {
                    LabeledContent("Heart rate", value: "no source")
                }
                if let cal = workout.calories {
                    LabeledContent("Calories", value: "\(cal) kcal")
                }
                if let effort = workout.perceivedEffort {
                    LabeledContent("Effort", value: "\(effort) / 10")
                }
                if let notes = workout.workoutNotes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Segments") {
                let sortedSegs = workout.segments.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(sortedSegs) { seg in
                    cyclingSegmentRow(seg)
                }
            }
        }
        .navigationTitle(workout.templateName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: WorkoutExportService.exportCyclingJSON(workout),
                    preview: SharePreview(
                        "\(workout.templateName).json",
                        image: Image(systemName: "doc.text")
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func cyclingSegmentRow(_ seg: SDCyclingSegmentLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: kindIcon(seg.kind))
                    .foregroundStyle(kindColor(seg.kind))
                    .font(.caption)
                Text(seg.name).font(.subheadline)
                Spacer()
                Text(formatDuration(seg.durationSecondsActual))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if seg.skipped {
                    Text("skipped")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 10) {
                if let lo = seg.targetMinBpm, let hi = seg.targetMaxBpm {
                    Label("target \(lo)-\(hi)", systemImage: "scope")
                }
                if let avg = seg.averageHr {
                    Label("avg \(avg)", systemImage: "heart")
                }
                if let max = seg.maxHr {
                    Label("max \(max)", systemImage: "arrow.up")
                }
                if let pct = seg.inZonePct {
                    Label("\(pct)% in zone", systemImage: "target")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "warmup": "thermometer.sun"
        case "work": "flame.fill"
        case "recovery": "leaf.fill"
        case "cooldown": "snowflake"
        case "steady": "equal"
        default: "circle"
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "warmup": .orange
        case "work": .red
        case "recovery": .green
        case "cooldown": .blue
        case "steady": .purple
        default: .secondary
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Weight formatting

/// Formats a weight in kg, omitting the decimal when it is an integer.
/// 100.0 -> "100"; 102.5 -> "102.5"; 22.5 -> "22.5".
private func formatWeight(_ kg: Double) -> String {
    if kg.rounded() == kg {
        return String(Int(kg))
    }
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    formatter.decimalSeparator = "."
    return formatter.string(from: NSNumber(value: kg)) ?? "\(kg)"
}
