import SwiftUI

struct ActiveWorkoutView: View {
    @Bindable var vm: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(
                        Array(vm.exercises.enumerated()),
                        id: \.element.id
                    ) { idx, _ in
                        ExerciseCard(
                            exerciseIndex: idx,
                            vm: vm
                        )
                    }
                }
                .padding()
                .padding(.bottom, vm.restTimer.isRunning ? 100 : 0)
            }

            RestTimerView(vm: vm)
                .padding(.bottom, 8)
        }
        .navigationTitle(vm.exercises.isEmpty ? "Workout" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("\(vm.completedSetsCount)/\(vm.totalSetsCount) sets")
                        .font(.subheadline.weight(.medium))
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") {
                    vm.beginFinishing()
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
                    TextField("How did it go?", text: $vm.finishNotes, axis: .vertical)
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
                    Button("Back") {
                        vm.cancelFinishing()
                    }
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
