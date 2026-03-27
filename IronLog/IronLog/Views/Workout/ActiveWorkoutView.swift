import SwiftUI

struct ActiveWorkoutView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @State private var showDebugLog = false
    #endif

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
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            Button {
                showDebugLog = true
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showDebugLog) {
            DebugLogView(vm: vm)
        }
        #endif
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

            Spacer()

            SlideButton(
                leftLabel: weightLabel,
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

    private var weightLabel: String {
        let w = vm.currentSet?.weightKg ?? vm.lastCompletedWeight ?? 0
        return "\(formatted(w)) kg"
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

            Text(vm.setStopwatch.formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))

            Spacer()

            SlideButton(
                leftLabel: repsLabel,
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

    private var repsLabel: String {
        let reps = vm.currentSet?.prescribedReps ?? 0
        return "\(reps) reps"
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
                Text("Finish Set")
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
            reps = vm.currentSet?.prescribedReps ?? 10
        }
    }
}

// MARK: - Resting Phase

private struct RestingPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 20) {
            ExerciseHeader(vm: vm)

            CompletedSetsSummary(vm: vm)

            Spacer()

            // Circle timer button
            Button {
                vm.onRestFinished()
            } label: {
                let overtime = vm.restTimer.isOvertime
                VStack(spacing: 8) {
                    Text(vm.restTimer.formattedTime)
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                    Text(nextLabel)
                        .font(.callout.weight(.semibold))
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white)
                .frame(width: 220, height: 220)
                .background(
                    Circle().fill(overtime ? .yellow.opacity(0.3) : .blue.opacity(0.25))
                )
                .overlay {
                    Circle()
                        .stroke(overtime ? .yellow.opacity(0.2) : .blue.opacity(0.2), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: 1.0 - vm.restTimer.progress)
                        .stroke(
                            overtime ? .yellow : .blue,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: vm.restTimer.progress)
                }
            }
            .buttonStyle(.plain)
            .shadow(color: vm.restTimer.isOvertime ? .yellow.opacity(0.4) : .blue.opacity(0.4), radius: 12)

            Spacer()
            Spacer()
        }
        .padding()
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
            Button { weight = max(0, weight - 1) } label: {
                Image(systemName: "minus.circle.fill").font(.title)
            }
            .tint(.secondary)

            TextField(
                "0",
                value: $weight,
                format: .number.precision(.fractionLength(0))
            )
            .font(.system(size: 40, weight: .bold, design: .monospaced))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .frame(width: 140)
            .focused($isFocused)

            Text("kg")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button { weight += 1 } label: {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .tint(.secondary)
        }
    }
}

private struct ExerciseListMenu: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        let indexed = Array(vm.exercises.enumerated())
        let incomplete = indexed.filter { !$0.element.sets.allSatisfy(\.isCompleted) }
        let completed = indexed.filter { $0.element.sets.allSatisfy(\.isCompleted) }

        Menu {
            ForEach(incomplete, id: \.element.id) { idx, ex in
                Button {
                    vm.jumpToExercise(idx)
                } label: {
                    Label(ex.name, systemImage: "circle")
                }
            }

            if !completed.isEmpty {
                Divider()
                ForEach(completed, id: \.element.id) { idx, ex in
                    Button {
                        vm.jumpToExercise(idx)
                    } label: {
                        Label(ex.name, systemImage: "checkmark.circle.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }
}

private func formatted(_ value: Double) -> String {
    String(format: "%.0f", value)
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
