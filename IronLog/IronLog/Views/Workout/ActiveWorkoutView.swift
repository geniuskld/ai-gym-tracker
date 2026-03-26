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
            case .enteringWeight:
                WeightEntryView(vm: vm)
            case .enteringReps:
                RepsEntryView(vm: vm)
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
                Button("Finish") {
                    vm.beginFinishing()
                }
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

// MARK: - Ready Phase (START button)

private struct ReadyPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)

            Text("SET \(vm.currentSetIndex + 1) of \((vm.currentExercise?.sets.count ?? 0))")
                .font(.title3.weight(.bold))

            if !vm.prescribedHint.isEmpty {
                Text(vm.prescribedHint)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Completed sets summary
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

            // Skip exercise
            Button("Skip exercise") {
                vm.skipExercise()
            }
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

            Text("SET \(vm.currentSetIndex + 1)")
                .font(.title3.weight(.bold))

            // Stopwatch
            Text(vm.setStopwatch.formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))
                .foregroundStyle(.primary)

            if !vm.prescribedHint.isEmpty {
                Text(vm.prescribedHint)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Slide button
            SlideButton(
                onSlideRight: { vm.completeSetDone() },
                onSlideLeft: { vm.openWeightEntry() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Weight Entry

private struct WeightEntryView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var weight: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Weight (kg)")
                .font(.title2.weight(.bold))

            HStack(spacing: 16) {
                Button {
                    weight = max(0, weight - 2.5)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                }
                .tint(.secondary)

                TextField(
                    "0",
                    value: $weight,
                    format: .number.precision(.fractionLength(1))
                )
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 160)
                .focused($focused)

                Button {
                    weight += 2.5
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
                .tint(.secondary)
            }

            // Quick weight buttons
            if let last = vm.lastCompletedWeight {
                Button("Use last: \(formatted(last)) kg") {
                    vm.setWeight(last)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                vm.setWeight(weight)
            } label: {
                Text("Confirm")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
        .onAppear {
            weight = vm.lastCompletedWeight ?? 0
            focused = true
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Reps Entry

private struct RepsEntryView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var reps: Int = 10

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let w = vm.currentSet?.weightKg {
                Text("\(formatted(w)) kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("Reps")
                .font(.title2.weight(.bold))

            HStack(spacing: 24) {
                Button {
                    reps = max(1, reps - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                .tint(.secondary)

                Text("\(reps)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .frame(width: 100)

                Button {
                    reps += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                }
                .tint(.secondary)
            }

            Spacer()

            Button {
                vm.setReps(reps)
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
            reps = vm.currentSet?.prescribedRepsMin ?? 10
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Resting Phase (countdown on button)

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

            Spacer()

            // Countdown on button - tap to skip and start next set
            let nextSetNum = vm.currentSetIndex + 2
            let totalSets = vm.currentExercise?.sets.count ?? 0

            Button {
                vm.skipRest()
            } label: {
                VStack(spacing: 4) {
                    if nextSetNum <= totalSets {
                        Text("START SET \(nextSetNum)")
                            .font(.title3.weight(.bold))
                    } else {
                        Text("NEXT EXERCISE")
                            .font(.title3.weight(.bold))
                    }
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

private struct CompletedSetsSummary: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        let completedSets = vm.currentExercise?.sets
            .filter(\.isCompleted) ?? []

        if !completedSets.isEmpty {
            VStack(spacing: 4) {
                ForEach(completedSets) { s in
                    HStack {
                        Text("Set \(s.setNumber)")
                            .font(.caption.weight(.medium))
                        if let w = s.weightKg {
                            Text("\(formatted(w)) kg")
                                .font(.caption)
                        }
                        if let r = s.reps {
                            Text("\(r) reps")
                                .font(.caption)
                        }
                    }
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
