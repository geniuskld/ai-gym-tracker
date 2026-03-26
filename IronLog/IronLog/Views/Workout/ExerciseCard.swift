import SwiftUI

struct ExerciseCard: View {
    let exerciseIndex: Int
    @Bindable var vm: ActiveWorkoutViewModel

    private var exercise: ExerciseState {
        vm.exercises[exerciseIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(exercise.name)
                    .font(.headline)

                Spacer()

                if exercise.technique != "straight" {
                    Text(techniqueName(exercise.technique))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            // Meta row
            HStack(spacing: 8) {
                Text(exercise.bodyPart)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let equip = exercise.equipment {
                    Text(equip.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if exercise.restSeconds > 0 {
                    Label(
                        "\(exercise.restSeconds)s",
                        systemImage: "timer"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let tempo = exercise.tempo {
                    Text(tempo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 2)
            }

            // Sets header
            HStack(spacing: 8) {
                Text("SET")
                    .frame(width: 40)
                Text("KG")
                    .frame(width: 64)
                Text("REPS")
                    .frame(width: 56)
                Spacer()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)

            // Set rows
            ForEach(
                Array(exercise.sets.enumerated()),
                id: \.element.id
            ) { setIdx, _ in
                SetRowView(
                    exerciseIndex: exerciseIndex,
                    setIndex: setIdx,
                    vm: vm
                )
            }

            // Add set
            Button {
                vm.addSet(exerciseIndex: exerciseIndex)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func techniqueName(_ technique: String) -> String {
        technique.replacingOccurrences(of: "_", with: " ")
    }
}
