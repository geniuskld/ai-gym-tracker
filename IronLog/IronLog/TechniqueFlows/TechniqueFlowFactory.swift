import Foundation

enum TechniqueFlowFactory {

    /// Creates the appropriate TechniqueFlow for the exercise at the given index.
    /// For supersets, creates a SupersetFlow covering both paired exercises.
    static func makeFlow(
        for exerciseIndex: Int,
        exercises: [ExerciseState]
    ) -> any TechniqueFlow {
        guard exercises.indices.contains(exerciseIndex) else {
            assertionFailure("Invalid exerciseIndex \(exerciseIndex) for exercises count \(exercises.count)")
            return StraightFlow(exerciseIndex: exerciseIndex)
        }
        let exercise = exercises[exerciseIndex]

        switch exercise.technique {
        case "drop_set":
            return DropSetFlow(exerciseIndex: exerciseIndex)

        case "superset":
            if let partnerIdx = exercise.supersetPartnerIndex,
               exercises.indices.contains(partnerIdx),
               partnerIdx != exerciseIndex {
                // Always use the lower index as primary
                let primary = min(exerciseIndex, partnerIdx)
                let partner = max(exerciseIndex, partnerIdx)
                return SupersetFlow(
                    primaryIndex: primary,
                    partnerIndex: partner
                )
            }
            return StraightFlow(exerciseIndex: exerciseIndex)

        case "rest_pause":
            return RestPauseFlow(exerciseIndex: exerciseIndex)

        case "myo_reps":
            let limit = exercise.maxMiniSets ?? 5
            return MyoRepsFlow(exerciseIndex: exerciseIndex, maxMiniSets: limit)

        default:
            return StraightFlow(exerciseIndex: exerciseIndex)
        }
    }
}
