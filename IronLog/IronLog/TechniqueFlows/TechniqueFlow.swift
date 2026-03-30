import Foundation

/// Describes what the user should do next.
struct TechniqueStep {
    /// Index of the exercise in the exercises array
    let exerciseIndex: Int
    /// Index of the set within that exercise
    let setIndex: Int
    /// Instruction text shown to the user (e.g. "Drop to 14 kg, go!")
    let instruction: String
    /// Pre-calculated weight for this step
    let suggestedWeightKg: Double?
    /// Rest seconds before this step. nil = no rest (go immediately).
    let restSeconds: Int?
    /// Prescribed reps hint for this step
    let prescribedReps: Int?
    /// True if this is the last step in the technique
    let isTerminal: Bool
}

/// Each technique (straight, drop_set, superset, etc.) implements this protocol.
/// The flow is stateless -- it reads isCompleted flags from exercises to determine next step.
protocol TechniqueFlow {
    /// Display name for UI badge (e.g. "Drop set")
    var displayName: String? { get }

    /// Exercise indices this flow controls
    var exerciseIndices: [Int] { get }

    /// Returns the next step to present, or nil if the technique is fully complete.
    /// - Parameters:
    ///   - exercises: current snapshot of all exercise states
    ///   - completedExerciseIndex: exercise whose set just finished (nil on initial call)
    ///   - completedSetIndex: set that just finished (nil on initial call)
    ///   - completedReps: reps the user actually did (nil on initial call)
    func nextStep(
        exercises: [ExerciseState],
        completedExerciseIndex: Int?,
        completedSetIndex: Int?,
        completedReps: Int?
    ) -> TechniqueStep?

    /// Whether this flow can dynamically add sets (myo-reps mini-sets)
    var supportsDynamicSets: Bool { get }
}

extension TechniqueFlow {
    var supportsDynamicSets: Bool { false }
    var displayName: String? { nil }
}
