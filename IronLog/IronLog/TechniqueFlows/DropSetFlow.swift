import Foundation

/// Drop set: working set -> drop (no rest, auto-reduce weight) -> rest -> repeat
struct DropSetFlow: TechniqueFlow {
    let exerciseIndex: Int
    var exerciseIndices: [Int] { [exerciseIndex] }
    var displayName: String? { "Drop set" }

    func nextStep(
        exercises: [ExerciseState],
        completedExerciseIndex: Int?,
        completedSetIndex: Int?,
        completedReps: Int?
    ) -> TechniqueStep? {
        let ex = exercises[exerciseIndex]

        guard let nextSetIdx = ex.sets.firstIndex(where: { !$0.isCompleted }) else {
            return nil
        }

        let nextSet = ex.sets[nextSetIdx]
        let isFirstStep = completedExerciseIndex == nil

        if nextSet.type == "drop" {
            // Drop set: no rest, auto-reduce weight from last working set
            let baseWeight = lastWorkingWeight(ex) ?? 0
            let pct = nextSet.prescribedWeightPercentDrop ?? 0.3
            let dropWeight = max(1, (baseWeight * (1 - pct)).rounded())

            return TechniqueStep(
                exerciseIndex: exerciseIndex,
                setIndex: nextSetIdx,
                instruction: "Drop to \(Int(dropWeight)) kg -- no rest!",
                suggestedWeightKg: dropWeight,
                restSeconds: nil, // no rest before drop
                prescribedReps: nextSet.prescribedReps,
                isTerminal: nextSetIdx == ex.sets.count - 1,
                lockWeight: true
            )
        } else {
            // Working set: rest after previous (unless first)
            let weight = lastWorkingWeight(ex) ?? nextSet.weightKg

            // Rest only if we just completed a drop set (end of a working+drop pair)
            let justFinishedDrop: Bool
            if let completedIdx = completedSetIndex {
                justFinishedDrop = ex.sets[completedIdx].type == "drop"
            } else {
                justFinishedDrop = false
            }

            let restSeconds: Int?
            if isFirstStep {
                restSeconds = nil
            } else if justFinishedDrop {
                restSeconds = ex.restSeconds
            } else {
                // This shouldn't normally happen (working after working in drop_set technique)
                restSeconds = ex.restSeconds
            }

            return TechniqueStep(
                exerciseIndex: exerciseIndex,
                setIndex: nextSetIdx,
                instruction: formatInstruction(
                    set: nextSet,
                    setNumber: nextSetIdx + 1,
                    totalSets: ex.sets.count
                ),
                suggestedWeightKg: weight,
                restSeconds: restSeconds,
                prescribedReps: nextSet.prescribedReps,
                isTerminal: nextSetIdx == ex.sets.count - 1
            )
        }
    }
}
