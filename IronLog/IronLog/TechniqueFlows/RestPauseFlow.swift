import Foundation

/// Rest-pause: to failure -> 15-20s pause -> to failure -> 15-20s -> ... -> done
struct RestPauseFlow: TechniqueFlow {
    let exerciseIndex: Int
    var exerciseIndices: [Int] { [exerciseIndex] }
    var displayName: String? { "Rest-pause" }

    /// Short intra-set pause for rest-pause technique
    private let intraPauseSeconds = 20

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
        let weight = lastWorkingWeight(ex) ?? nextSet.weightKg
        let isFirstStep = completedExerciseIndex == nil

        let instruction: String
        if isFirstStep {
            instruction = "Go to failure"
        } else {
            instruction = "Continue to failure"
        }

        // Short pause between sets (20s), no pause before first
        let restSeconds = isFirstStep ? nil : intraPauseSeconds

        return TechniqueStep(
            exerciseIndex: exerciseIndex,
            setIndex: nextSetIdx,
            instruction: instruction,
            suggestedWeightKg: weight,
            restSeconds: restSeconds,
            prescribedReps: nextSet.prescribedReps,
            isTerminal: nextSetIdx == ex.sets.count - 1
        )
    }
}
