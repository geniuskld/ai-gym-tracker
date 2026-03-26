import SwiftUI

struct ActiveWorkoutView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(
                value: Double(vm.completedSetsCount),
                total: Double(max(vm.totalSetsCount, 1))
            )
            .tint(.green)

            switch vm.setPhase {
            case .ready:
                ReadyPhaseView(vm: vm)
            case .performing:
                PerformingPhaseView(vm: vm)
            case .logEntry(let weightPrefilled):
                LogEntryView(vm: vm, weightPrefilled: weightPrefilled)
            case .resting:
                RestingPhaseView(vm: vm)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(vm.completedExercisesCount)/\(vm.exercises.count)")
                    .font(.subheadline.weight(.medium))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") { vm.beginFinishing() }
                    .font(.subheadline)
            }
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    ForEach(
                        Array(vm.exercises.enumerated()),
                        id: \.element.id
                    ) { idx, ex in
                        Button {
                            vm.jumpToExercise(idx)
                        } label: {
                            HStack {
                                Text(ex.name)
                                if ex.sets.allSatisfy(\.isCompleted) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
        }
        .sheet(isPresented: isFinishing) {
            FinishWorkoutSheet(vm: vm)
        }
        .onChange(of: vm.state) { _, newState in
            if case .saved = newState {
                vm.reset()
                dismiss()
            }
        }
    }

    private var isFinishing: Binding<Bool> {
        Binding(
            get: {
                if case .finishing = vm.state { return true }
                return false
            },
            set: { if !$0 { vm.cancelFinishing() } }
        )
    }
}

// MARK: - Ready Phase (first set of exercise)

private struct ReadyPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)

            SetBadge(vm: vm)

            CompletedSetsSummary(vm: vm)

            Spacer()

            Button {
                vm.startSet()
            } label: {
                Text("START")
                    .font(.largeTitle.weight(.heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 32)

            Button("Skip exercise") { vm.skipExercise() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .padding()
    }
}

// MARK: - Performing Phase (stopwatch + slide button)

private struct PerformingPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)

            SetBadge(vm: vm)

            Text(vm.setStopwatch.formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))

            Spacer()

            SlideButton(
                onSlideRight: { vm.slideRight() },
                onSlideLeft: { vm.slideLeft() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Log Entry (weight + reps on one screen)

private struct LogEntryView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    let weightPrefilled: Bool

    @State private var weight: Double = 0
    @State private var reps: Int = 10
    @FocusState private var weightFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Weight section
            Text("Weight")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button { weight = max(0, weight - 2.5) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                }
                .tint(.secondary)

                TextField(
                    "0",
                    value: $weight,
                    format: .number.precision(.fractionLength(1))
                )
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 140)
                .focused($weightFocused)

                Text("kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button { weight += 2.5 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                }
                .tint(.secondary)
            }

            Divider().padding(.horizontal, 48)

            // Reps section
            Text("Reps")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button { reps = max(1, reps - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 40))
                }
                .tint(.secondary)

                Text("\(reps)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .frame(width: 80)

                Button { reps += 1 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                }
                .tint(.secondary)
            }

            if !vm.prescribedHint.isEmpty {
                Text(vm.prescribedHint)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                vm.logSet(weightKg: weight, reps: reps)
            } label: {
                Text("Log Set")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
        .onAppear {
            weight = vm.currentSet?.weightKg ?? vm.lastCompletedWeight ?? 0
            reps = vm.currentSet?.prescribedRepsMin ?? 10
            if !weightPrefilled {
                weightFocused = true
            }
        }
    }
}

// MARK: - Resting Phase (countdown -> auto start next set)

private struct RestingPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)

            Text("Rest")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text(vm.restTimer.formattedTime)
                .font(.system(size: 72, weight: .thin, design: .monospaced))

            ProgressView(value: vm.restTimer.progress)
                .tint(.blue)
                .padding(.horizontal, 48)

            CompletedSetsSummary(vm: vm)

            Spacer()

            Button {
                vm.skipRest()
            } label: {
                VStack(spacing: 4) {
                    Text(nextLabel)
                        .font(.title3.weight(.bold))
                    Text(vm.restTimer.formattedTime)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue.opacity(0.8))
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
        .onChange(of: vm.restTimer.isRunning) { _, running in
            if !running && vm.setPhase == .resting {
                vm.onRestFinished()
            }
        }
    }

    private var nextLabel: String {
        let nextSetNum = vm.currentSetIndex + 2
        let totalSets = vm.currentExercise?.sets.count ?? 0
        if nextSetNum <= totalSets {
            return "SET \(nextSetNum)"
        }
        return "NEXT"
    }
}

// MARK: - Shared components

private struct ExerciseHeader: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        if let ex = vm.currentExercise {
            VStack(spacing: 6) {
                Text(ex.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if let notes = ex.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}

private struct SetBadge: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text("SET \(vm.currentSetIndex + 1) of \(vm.currentExercise?.sets.count ?? 0)")
                .font(.title3.weight(.bold))

            if !vm.prescribedHint.isEmpty {
                Text(vm.prescribedHint)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompletedSetsSummary: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        let completedSets = vm.currentExercise?.sets
            .filter(\.isCompleted) ?? []

        if !completedSets.isEmpty {
            VStack(spacing: 4) {
                ForEach(completedSets) { s in
                    HStack(spacing: 8) {
                        Text("Set \(s.setNumber)")
                            .font(.caption.weight(.medium))
                        if let w = s.weightKg {
                            Text("\(formatted(w)) kg")
                        }
                        if let r = s.reps {
                            Text("\(r) reps")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Finish Sheet

private struct FinishWorkoutSheet: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var effort: Double = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Session RPE") {
                    VStack {
                        Text("\(Int(effort))")
                            .font(.title.weight(.bold))
                        Slider(value: $effort, in: 1...10, step: 1)
                    }
                }

                Section("Notes") {
                    TextField(
                        "How did it go?",
                        text: $vm.finishNotes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    HStack {
                        Text("Completed sets")
                        Spacer()
                        Text("\(vm.completedSetsCount) / \(vm.totalSetsCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { vm.cancelFinishing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.finishEffort = Int(effort)
                        vm.saveWorkout()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}
