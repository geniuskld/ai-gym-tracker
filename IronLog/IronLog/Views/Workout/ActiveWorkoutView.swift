import SwiftUI

struct ActiveWorkoutView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showNoteSheet = false
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
            case .performing:
                PerformingPhaseView(vm: vm)
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
                HStack(spacing: 12) {
                    Button { showNoteSheet = true } label: {
                        let hasNote = !vm.exerciseNote(at: vm.currentExerciseIndex).isEmpty
                        Image(systemName: hasNote ? "note.text" : "note.text.badge.plus")
                            .font(.subheadline)
                    }
                    Button("Finish") { vm.beginFinishing() }
                        .font(.subheadline)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                ExerciseListButton(vm: vm)
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            ExerciseNoteSheet(vm: vm)
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
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: { vm.persistenceErrorMessage != nil },
                set: { if !$0 { vm.persistenceErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                vm.persistenceErrorMessage = nil
            }
        } message: {
            Text(vm.persistenceErrorMessage ?? "")
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

            if !vm.flowInstruction.isEmpty {
                let isDrop = vm.currentSet?.type == "drop"
                Text(vm.flowInstruction)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isDrop ? .orange : .primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            SetRoadmap(vm: vm)

            Spacer()

            // Weight preview (will be adjustable on performing screen)
            let w = vm.currentSet?.weightKg ?? vm.lastCompletedWeight ?? 0
            if w > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(formatted(w))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("kg")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                vm.readySlideRight()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
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

// MARK: - Performing Phase: weight + reps adjustable, Done to finish

private struct PerformingPhaseView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var weight: Double = 0
    @State private var reps: Int = 10

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Timer -- hero element
            Text(vm.setStopwatch.formattedTime)
                .font(.system(size: 72, weight: .thin, design: .monospaced))
                .monospacedDigit()

            Spacer()

            // Weight + reps -- compact row
            HStack(spacing: 24) {
                // Weight
                if vm.flowLockWeight {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(weight))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button { weight = max(0, weight - 1) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                        }
                        .tint(.secondary)
                        .accessibilityLabel("Decrease weight")
                        .accessibilityValue("\(Int(weight)) kg")

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(weight))")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("kg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 64)

                        Button { weight += 1 } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                        }
                        .tint(.secondary)
                        .accessibilityLabel("Increase weight")
                        .accessibilityValue("\(Int(weight)) kg")
                    }
                }

                // Divider
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 1, height: 32)

                // Reps
                HStack(spacing: 8) {
                    Button { reps = max(1, reps - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Decrease reps")
                    .accessibilityValue("\(reps)")

                    VStack(spacing: 0) {
                        Text("\(reps)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("reps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44)

                    Button { reps += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Increase reps")
                    .accessibilityValue("\(reps)")
                }
            }
            .padding(.bottom, 32)

            // Done button
            Button {
                vm.confirmPerforming(weight: weight, reps: reps)
            } label: {
                Text("Done")
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
            SetRoadmap(vm: vm, condensed: true)

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
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 180)
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

            // Show rating buttons during rest before next exercise
            if vm.isRestBeforeNextExercise {
                InlineRatingBar(vm: vm)
                    .padding(.bottom, 16)
            } else if vm.isDynamicFlow {
                Button("Finish exercise") { vm.finishExercise() }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 16)
            } else {
                Spacer()
            }
        }
        .padding()
    }

    private var nextLabel: String {
        // Rest before next exercise
        if vm.isRestBeforeNextExercise {
            if let name = vm.nextExerciseName {
                return name
            }
            return "NEXT EXERCISE"
        }
        // Flow instruction (e.g. "Drop to 70 kg")
        if !vm.flowInstruction.isEmpty {
            return vm.flowInstruction
        }
        // Next set within current exercise
        let nextSetNum = vm.currentSetIndex + 1
        let totalSets = vm.currentExercise?.sets.count ?? 0
        return nextSetNum <= totalSets ? "SET \(nextSetNum)" : "DONE"
    }
}

// MARK: - Shared

private struct ExerciseHeader: View {
    let vm: ActiveWorkoutViewModel
    var body: some View {
        if let ex = vm.currentExercise {
            VStack(spacing: 6) {
                // Superset: prominent label + both exercises
                if let partnerIdx = ex.supersetPartnerIndex {
                    Label("Superset", systemImage: "arrow.triangle.2.circlepath")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.purple)

                    Text(ex.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(vm.exercises[partnerIdx].name)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(ex.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    // Technique badge (non-superset) -- large so user notices the technique
                    if let name = vm.currentFlow?.displayName {
                        Text(name.uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(techniqueBadgeColor(ex.technique))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(techniqueBadgeColor(ex.technique).opacity(0.15), in: Capsule())
                    }
                }

                if let notes = ex.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func techniqueBadgeColor(_ technique: String) -> Color {
        switch technique {
        case "drop_set":   return .orange
        case "rest_pause": return .blue
        case "myo_reps":   return .purple
        default:           return .secondary
        }
    }
}

private struct SetRoadmap: View {
    let vm: ActiveWorkoutViewModel
    var condensed: Bool = false

    var body: some View {
        guard let ex = vm.currentExercise else { return AnyView(EmptyView()) }
        let sets = ex.sets
        let activeIdx = vm.currentSetIndex

        // For myo-reps with many sets, show condensed summary
        if condensed && sets.count > 6 {
            return AnyView(condensedView(sets: sets))
        }

        return AnyView(
            VStack(spacing: 2) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { idx, s in
                    setRow(s, index: idx, isActive: idx == activeIdx)
                }
            }
            .padding(.vertical, 8)
        )
    }

    private func setRow(_ s: SetState, index: Int, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            // Set number / checkmark
            if s.isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 20)
            } else {
                Text("\(index + 1).")
                    .font(.caption.weight(isActive ? .bold : .regular))
                    .frame(width: 20)
            }

            // Type label
            let typeLabel = setTypeLabel(s.type)
            if !typeLabel.isEmpty {
                Text(typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(setTypeColor(s.type))
            }

            // Reps
            if let r = s.isCompleted ? s.reps : s.prescribedReps {
                Text("\(r) reps")
                    .font(.caption)
            }

            // Weight
            if let w = s.isCompleted ? s.weightKg : (s.weightKg ?? s.prescribedWeightKg) {
                Text("\(formatted(w)) kg")
                    .font(.caption)
            }

            // RIR
            if !s.isCompleted, let rir = s.prescribedRir {
                Text("RIR \(rir)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .foregroundStyle(rowStyle(isCompleted: s.isCompleted, isActive: isActive))
        .fontWeight(isActive ? .bold : .regular)
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    private func rowStyle(isCompleted: Bool, isActive: Bool) -> some ShapeStyle {
        if isActive { return AnyShapeStyle(.primary) }
        if isCompleted { return AnyShapeStyle(.tertiary) }
        return AnyShapeStyle(.secondary)
    }

    private func setTypeLabel(_ type: String) -> String {
        switch type {
        case "warmup": return "Warmup"
        case "drop": return "Drop"
        case "myo_mini": return "Mini"
        default: return ""
        }
    }

    private func setTypeColor(_ type: String) -> Color {
        switch type {
        case "warmup": return .blue
        case "drop": return .orange
        case "myo_mini": return .purple
        default: return .secondary
        }
    }

    private func condensedView(sets: [SetState]) -> some View {
        let done = sets.filter(\.isCompleted)
        let totalReps = done.compactMap(\.reps).reduce(0, +)
        return Text("\(done.count) sets done / \(totalReps) total reps")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

private struct WeightStepper: View {
    @Binding var weight: Double

    var body: some View {
        VStack(spacing: 12) {
            // Weight display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(weight))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                Text("kg")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // Step buttons
            HStack(spacing: 12) {
                stepButton(label: "-5", delta: -5)
                stepButton(label: "-1", delta: -1)
                stepButton(label: "+1", delta: 1)
                stepButton(label: "+5", delta: 5)
            }
        }
    }

    private func stepButton(label: String, delta: Double) -> some View {
        Button {
            weight = max(0, weight + delta)
        } label: {
            Text(label)
                .font(.title3.weight(.semibold))
                .frame(width: 64, height: 48)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
        .tint(.primary)
    }
}

private struct ExerciseListButton: View {
    let vm: ActiveWorkoutViewModel
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "list.bullet")
        }
        .sheet(isPresented: $showSheet) {
            ExerciseListSheet(vm: vm, isPresented: $showSheet)
        }
    }
}

private struct ExerciseListSheet: View {
    let vm: ActiveWorkoutViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { idx, ex in
                        let isCurrent = idx == vm.currentExerciseIndex
                        let doneSets = ex.sets.filter(\.isCompleted).count
                        let totalSets = ex.sets.count
                        let allDone = doneSets == totalSets

                        Button {
                            vm.jumpToExercise(idx)
                            isPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                // Status icon
                                ZStack {
                                    Circle()
                                        .fill(statusColor(
                                            isCurrent: isCurrent,
                                            allDone: allDone
                                        ).opacity(0.15))
                                        .frame(width: 36, height: 36)

                                    if allDone {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.green)
                                    } else if isCurrent {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    } else {
                                        Text("\(idx + 1)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Exercise info
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ex.name)
                                        .font(.subheadline.weight(
                                            isCurrent ? .bold : .regular
                                        ))
                                        .foregroundStyle(
                                            allDone ? .secondary : .primary
                                        )
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        // Body part
                                        Text(bodyPartLabel(ex.bodyPart))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)

                                        // Technique badge
                                        if ex.technique != "straight" {
                                            Text(techniqueName(ex.technique))
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(
                                                    techniqueColor(ex.technique)
                                                )
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(
                                                    techniqueColor(ex.technique)
                                                        .opacity(0.12),
                                                    in: Capsule()
                                                )
                                        }
                                    }
                                }

                                Spacer()

                                // Progress
                                if allDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.body)
                                } else {
                                    Text("\(doneSets)/\(totalSets)")
                                        .font(.caption.weight(.medium).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            isCurrent
                                ? Color.blue.opacity(0.08)
                                : Color.clear
                        )
                        .id(idx)
                    }
                }
                .listStyle(.plain)
                .navigationTitle("Exercises")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
                .onAppear {
                    proxy.scrollTo(vm.currentExerciseIndex, anchor: .center)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func statusColor(isCurrent: Bool, allDone: Bool) -> Color {
        if allDone { return .green }
        if isCurrent { return .blue }
        return .secondary
    }

    private func bodyPartLabel(_ part: String) -> String {
        switch part {
        case "legs": return "Legs"
        case "chest": return "Chest"
        case "back": return "Back"
        case "shoulders": return "Shoulders"
        case "biceps": return "Biceps"
        case "triceps": return "Triceps"
        case "core": return "Core"
        default: return part.capitalized
        }
    }

    private func techniqueName(_ technique: String) -> String {
        switch technique {
        case "drop_set": return "Drop"
        case "rest_pause": return "Rest-Pause"
        case "myo_reps": return "Myo"
        case "superset": return "Superset"
        default: return technique
        }
    }

    private func techniqueColor(_ technique: String) -> Color {
        switch technique {
        case "drop_set": return .orange
        case "rest_pause": return .blue
        case "myo_reps": return .purple
        case "superset": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Inline Exercise Rating (shown during rest before next exercise)

struct InlineRatingBar: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text("How did it feel?")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ratingButton("Heavy", icon: "flame.fill", color: .red, value: 3)
                ratingButton("OK", icon: "hand.thumbsup.fill", color: .blue, value: 2)
                ratingButton("Easy", icon: "wind", color: .green, value: 1)
            }
        }
        .padding(.horizontal, 16)
    }

    private func ratingButton(
        _ label: String,
        icon: String,
        color: Color,
        value: Int
    ) -> some View {
        let selected = vm.pendingRating == value
        return Button {
            vm.setPendingRating(value)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                color.opacity(selected ? 0.30 : 0.12),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color, lineWidth: selected ? 2 : 0)
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

private func formatted(_ value: Double) -> String {
    String(format: "%.0f", value)
}

// MARK: - Exercise Note Sheet

private struct ExerciseNoteSheet: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Coach notes (from plan) -- read-only
                if let coachNotes = vm.currentExercise?.notes,
                   !coachNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Coach", systemImage: "figure.strengthtraining.traditional")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(coachNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                // User note -- editable
                VStack(alignment: .leading, spacing: 4) {
                    Label("My note", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    TextEditor(text: $noteText)
                        .font(.body)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer()
            }
            .padding()
            .navigationTitle(vm.currentExercise?.name ?? "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.saveExerciseNote(
                            noteText,
                            forExerciseAt: vm.currentExerciseIndex
                        )
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                noteText = vm.exerciseNote(at: vm.currentExerciseIndex)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Finish Sheet

private struct FinishWorkoutSheet: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @State private var effort: PerceivedEffort = .moderate
    #if DEBUG
    @State private var skipHealthKit = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("How hard was it?") {
                    Picker("Effort", selection: $effort) {
                        ForEach(PerceivedEffort.allCases, id: \.self) { e in
                            Text(e.label).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    HStack {
                        Text("Completed sets")
                        Spacer()
                        Text("\(vm.completedSetsCount) / \(vm.totalSetsCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                Section {
                    Toggle("Skip Apple Health", isOn: $skipHealthKit)
                }
                #endif
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { vm.cancelFinishing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.finishEffort = effort.logValue
                        #if DEBUG
                        vm.skipHealthKit = skipHealthKit
                        #endif
                        vm.saveWorkout()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

enum PerceivedEffort: String, CaseIterable {
    case easy, moderate, hard

    var label: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }

    var logValue: Int {
        switch self {
        case .easy: 1
        case .moderate: 2
        case .hard: 3
        }
    }
}
