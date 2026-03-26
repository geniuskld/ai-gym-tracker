import SwiftUI

struct SetRowView: View {
    let exerciseIndex: Int
    let setIndex: Int
    @Bindable var vm: ActiveWorkoutViewModel

    private var setState: SetState {
        vm.exercises[exerciseIndex].sets[setIndex]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set number + type badge
            VStack(spacing: 2) {
                Text("\(setState.setNumber)")
                    .font(.caption.weight(.bold))
                    .frame(width: 24)
                if setState.type != "working" {
                    Text(shortType(setState.type))
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(badgeColor(setState.type))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 40)

            // Weight input
            VStack(spacing: 1) {
                TextField(
                    "kg",
                    value: weightBinding,
                    format: .number
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            }

            // Reps input
            TextField(
                "reps",
                value: repsBinding,
                format: .number
            )
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: 56)

            // Prescribed hint
            if let hint = prescribedHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Failed toggle
            if setState.isCompleted && setState.failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // Complete button
            Button {
                if !setState.isCompleted {
                    vm.completeSet(
                        exerciseIndex: exerciseIndex,
                        setIndex: setIndex
                    )
                }
            } label: {
                Image(systemName: setState.isCompleted
                    ? "checkmark.circle.fill"
                    : "circle")
                    .font(.title3)
                    .foregroundStyle(setState.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .opacity(setState.isCompleted ? 0.7 : 1.0)
        .contextMenu {
            Button(role: .destructive) {
                vm.removeSet(
                    exerciseIndex: exerciseIndex,
                    setIndex: setIndex
                )
            } label: {
                Label("Remove Set", systemImage: "trash")
            }

            Button {
                vm.toggleFailed(
                    exerciseIndex: exerciseIndex,
                    setIndex: setIndex
                )
            } label: {
                Label(
                    setState.failed ? "Unmark Failed" : "Mark Failed",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    // MARK: - Bindings

    private var weightBinding: Binding<Double?> {
        Binding(
            get: { vm.exercises[exerciseIndex].sets[setIndex].weightKg },
            set: { vm.exercises[exerciseIndex].sets[setIndex].weightKg = $0 }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { vm.exercises[exerciseIndex].sets[setIndex].reps },
            set: { vm.exercises[exerciseIndex].sets[setIndex].reps = $0 }
        )
    }

    // MARK: - Helpers

    private var prescribedHint: String? {
        let s = setState
        var parts: [String] = []
        if let min = s.prescribedRepsMin, let max = s.prescribedRepsMax {
            parts.append(min == max ? "\(min)" : "\(min)-\(max)")
        }
        if let rir = s.prescribedRir {
            parts.append("RIR \(rir)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func shortType(_ type: String) -> String {
        switch type {
        case "warmup": return "W"
        case "drop": return "D"
        case "backoff": return "B"
        default: return type.prefix(1).uppercased()
        }
    }

    private func badgeColor(_ type: String) -> Color {
        switch type {
        case "warmup": return .orange
        case "drop": return .purple
        case "backoff": return .teal
        default: return .gray
        }
    }
}
