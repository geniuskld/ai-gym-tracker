import Foundation

/// Superset: exercise A set -> exercise B set (no rest) -> rest -> repeat
struct SupersetFlow: TechniqueFlow {
    let primaryIndex: Int
    let partnerIndex: Int
    var exerciseIndices: [Int] { [primaryIndex, partnerIndex] }
    var displayName: String? { "Superset" }

    func nextStep(
        exercises: [ExerciseState],
        completedExerciseIndex: Int?,
        completedSetIndex: Int?,
        completedReps: Int?
    ) -> TechniqueStep? {
        let primary = exercises[primaryIndex]
        let partner = exercises[partnerIndex]

        // Find current round (0-based) = first round where either exercise has incomplete set
        let maxRounds = max(primary.sets.count, partner.sets.count)

        for round in 0..<maxRounds {
            let primaryDone = round < primary.sets.count
                ? primary.sets[round].isCompleted
                : true
            let partnerDone = round < partner.sets.count
                ? partner.sets[round].isCompleted
                : true

            if primaryDone && partnerDone {
                continue // both done for this round
            }

            if !primaryDone {
                // Primary needs to do this round
                let weight = lastWorkingWeight(primary) ?? primary.sets[round].weightKg

                // Rest before this round (not before the very first step)
                let needsRest = completedExerciseIndex != nil && round > 0

                return TechniqueStep(
                    exerciseIndex: primaryIndex,
                    setIndex: round,
                    instruction: "\(primary.name): \(formatSetHint(primary.sets[round]))",
                    suggestedWeightKg: weight,
                    restSeconds: needsRest ? primary.restSeconds : nil,
                    prescribedReps: primary.sets[round].prescribedReps,
                    isTerminal: false
                )
            }

            if !partnerDone {
                // Partner needs to do this round (no rest -- go immediately)
                let weight = lastWorkingWeight(partner) ?? partner.sets[round].weightKg

                return TechniqueStep(
                    exerciseIndex: partnerIndex,
                    setIndex: round,
                    instruction: "Now: \(partner.name)",
                    suggestedWeightKg: weight,
                    restSeconds: nil, // no rest between superset pair
                    prescribedReps: partner.sets[round].prescribedReps,
                    isTerminal: false
                )
            }
        }

        return nil // all rounds done
    }

    private func formatSetHint(_ set: SetState) -> String {
        var parts: [String] = []
        if let reps = set.prescribedReps { parts.append("\(reps) reps") }
        if let rir = set.prescribedRir { parts.append("RIR \(rir)") }
        return parts.joined(separator: ", ")
    }
}
