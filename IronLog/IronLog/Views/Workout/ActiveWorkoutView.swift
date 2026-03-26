import SwiftUI

struct ActiveWorkoutView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: Double(vm.completedSetsCount),
                total: Double(max(vm.totalSetsCount, 1))
            )
            .tint(.green)

            switch vm.setPhase {
            case .ready:
                ReadyPhaseView(vm: vm)
            case .setWeight:
                SetWeightView(vm: vm)
            case .performing:
                PerformingPhaseView(vm: vm)
            case .enterReps:
                EnterRepsView(vm: vm)
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
                ExerciseListMenu(vm: vm)
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

// MARK: - Ready Phase: slider right=start, left=set weight

private struct ReadyPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)
            SetBadge(vm: vm)
            CompletedSetsSummary(vm: vm)

            if let w = vm.currentSet?.weightKg ?? vm.lastCompletedWeight {
                Text("\(formatted(w)) kg")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SlideButton(
                leftLabel: "Weight",
                leftIcon: "scalemass",
                rightLabel: "Start",
                rightIcon: "play.fill",
                onSlideRight: { vm.readySlideRight() },
                onSlideLeft: { vm.readySlideLeft() }
            )
            .padding(.horizontal, 24)

            Button("Skip exercise") { vm.skipExercise() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .padding()
    }
}

// MARK: - Set Weight (before starting)

private struct SetWeightView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var weight: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(vm.currentExercise?.name ?? "")
                .font(.title3.weight(.bold))

            Text("Set Weight")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            WeightStepper(weight: $weight)
                .focused($focused)

            Spacer()

            Button {
                vm.confirmWeightAndStart(weight)
            } label: {
                Text("Start Set")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
        .onAppear {
            weight = vm.lastCompletedWeight ?? 0
            focused = true
        }
    }
}

// MARK: - Performing Phase: slider right=done, left=enter reps

private struct PerformingPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ExerciseHeader(vm: vm)
            SetBadge(vm: vm)

            if let w = vm.currentSet?.weightKg {
                Text("\(formatted(w)) kg")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text(vm.setStopwatch.formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))

            Spacer()

            SlideButton(
                leftLabel: "Reps",
                leftIcon: "number",
                rightLabel: "Done",
                rightIcon: "checkmark",
                onSlideRight: { vm.performingSlideRight() },
                onSlideLeft: { vm.performingSlideLeft() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

// MARK: - Enter Reps (after performing, slide left)

private struct EnterRepsView: View {
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
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button { reps = max(1, reps - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                .tint(.secondary)

                Text("\(reps)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .frame(width: 100)

                Button { reps += 1 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
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
                vm.confirmReps(reps)
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
}

// MARK: - Resting Phase

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
        return nextSetNum <= totalSets ? "SET \(nextSetNum)" : "NEXT"
    }
}

// MARK: - Shared

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
        let done = vm.currentExercise?.sets.filter(\.isCompleted) ?? []
        if !done.isEmpty {
            VStack(spacing: 4) {
                ForEach(done) { s in
                    HStack(spacing: 8) {
                        Text("Set \(s.setNumber)")
                            .font(.caption.weight(.medium))
                        if let w = s.weightKg { Text("\(formatted(w)) kg") }
                        if let r = s.reps { Text("\(r) reps") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct WeightStepper: View {
    @Binding var weight: Double
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button { weight = max(0, weight - 2.5) } label: {
                Image(systemName: "minus.circle.fill").font(.title)
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
            .focused($isFocused)

            Text("kg")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button { weight += 2.5 } label: {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .tint(.secondary)
        }
    }
}

private struct ExerciseListMenu: View {
    let vm: ActiveWorkoutViewModel
    var body: some View {
        Menu {
            ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { idx, ex in
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

private func formatted(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
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
