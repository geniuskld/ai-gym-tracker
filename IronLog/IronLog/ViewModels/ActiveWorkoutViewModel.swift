import Foundation
import SwiftData

// MARK: - State types

struct SetState: Identifiable {
    let id = UUID()
    var setNumber: Int
    var type: String
    var weightKg: Double?
    var reps: Int?
    var rpe: Double?
    var rir: Int?
    var isCompleted: Bool = false
    var failed: Bool = false
    var setDurationSeconds: Int?

    // Prescribed hints
    var prescribedRepsMin: Int?
    var prescribedRepsMax: Int?
    var prescribedRir: Int?
    var prescribedWeightPercentDrop: Double?
}

struct ExerciseState: Identifiable {
    let id = UUID()
    let exerciseId: String
    let name: String
    let bodyPart: String
    let equipment: String?
    let technique: String
    let supersetWith: String?
    let restSeconds: Int
    let tempo: String?
    let notes: String?
    let stretchFocus: Bool
    var sets: [SetState]
}

// MARK: - Phases within a set

enum SetPhase: Equatable {
    case ready          // first set of exercise only
    case performing     // stopwatch running, slide button visible
    case logEntry(      // weight + reps on one screen
        weightPrefilled: Bool  // true = slide-right (weight carried over)
    )
    case resting        // countdown, auto-transitions to performing
}

// MARK: - ViewModel

@MainActor
@Observable
final class ActiveWorkoutViewModel {

    enum State: Equatable {
        case idle
        case active
        case loggingSet(exerciseIndex: Int, setIndex: Int)
        case restTimer
        case finishing
        case saved
    }

    // MARK: - Properties

    var state: State = .idle
    var exercises: [ExerciseState] = []
    var currentExerciseIndex: Int = 0
    var currentSetIndex: Int = 0
    var setPhase: SetPhase = .ready
    var restTimer = RestTimerService()
    var setStopwatch = StopwatchService()
    var finishNotes: String = ""
    var finishEffort: Int?

    private var workout: SDWorkout?
    private var modelContext: ModelContext?

    // MARK: - Computed

    var currentExercise: ExerciseState? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    var currentSet: SetState? {
        guard let ex = currentExercise,
              currentSetIndex < ex.sets.count else { return nil }
        return ex.sets[currentSetIndex]
    }

    var lastCompletedWeight: Double? {
        guard currentExerciseIndex < exercises.count else { return nil }
        let sets = exercises[currentExerciseIndex].sets
        for i in stride(from: currentSetIndex - 1, through: 0, by: -1) {
            if let w = sets[i].weightKg { return w }
        }
        return nil
    }

    var completedSetsCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    var totalSetsCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var completedExercisesCount: Int {
        exercises.filter { ex in ex.sets.allSatisfy(\.isCompleted) }.count
    }

    var prescribedHint: String {
        guard let s = currentSet else { return "" }
        var parts: [String] = []
        if s.type != "working" {
            parts.append(s.type.replacingOccurrences(of: "_", with: " "))
        }
        if let min = s.prescribedRepsMin, let max = s.prescribedRepsMax {
            parts.append(min == max ? "\(min) reps" : "\(min)-\(max) reps")
        }
        if let rir = s.prescribedRir {
            parts.append("RIR \(rir)")
        }
        return parts.joined(separator: " / ")
    }

    // MARK: - Start Workout

    func startWorkout(
        template: SDTemplate,
        context: ModelContext
    ) {
        modelContext = context

        let sdWorkout = SDWorkout(
            templateId: template.templateId,
            templateName: template.name
        )
        context.insert(sdWorkout)
        workout = sdWorkout

        let sortedGroups = template.groups.sorted { $0.sortOrder < $1.sortOrder }
        exercises = sortedGroups.flatMap { group in
            group.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { exercise in
                    let sortedSets = exercise.prescribedSets
                        .sorted { $0.sortOrder < $1.sortOrder }
                    let setStates = sortedSets.enumerated().map { idx, ps in
                        SetState(
                            setNumber: idx + 1,
                            type: ps.type,
                            prescribedRepsMin: ps.repsMin,
                            prescribedRepsMax: ps.repsMax,
                            prescribedRir: ps.rir,
                            prescribedWeightPercentDrop: ps.weightPercentDrop
                        )
                    }
                    return ExerciseState(
                        exerciseId: exercise.exerciseId,
                        name: exercise.name,
                        bodyPart: exercise.bodyPart,
                        equipment: exercise.equipment,
                        technique: exercise.technique,
                        supersetWith: exercise.supersetWith,
                        restSeconds: exercise.restSeconds,
                        tempo: exercise.tempo,
                        notes: exercise.notes,
                        stretchFocus: exercise.stretchFocus,
                        sets: setStates
                    )
                }
        }

        currentExerciseIndex = 0
        currentSetIndex = 0
        setPhase = .ready
        state = .active
    }

    // MARK: - Set Flow

    func startSet() {
        setPhase = .performing
        setStopwatch.start()
        state = .loggingSet(
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex
        )
    }

    func slideRight() {
        // Done = carry over last weight, go to log entry
        setStopwatch.stop()
        if let last = lastCompletedWeight {
            exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = last
        }
        setPhase = .logEntry(weightPrefilled: true)
    }

    func slideLeft() {
        // Open full log entry (weight + reps)
        setStopwatch.stop()
        setPhase = .logEntry(weightPrefilled: false)
    }

    func logSet(
        weightKg: Double,
        reps: Int
    ) {
        guard currentExerciseIndex < exercises.count,
              currentSetIndex < exercises[currentExerciseIndex].sets.count
        else { return }

        exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = weightKg
        exercises[currentExerciseIndex].sets[currentSetIndex].reps = reps
        exercises[currentExerciseIndex].sets[currentSetIndex].isCompleted = true
        exercises[currentExerciseIndex].sets[currentSetIndex].setDurationSeconds =
            setStopwatch.elapsedSeconds

        let restSeconds = exercises[currentExerciseIndex].restSeconds
        if restSeconds > 0 {
            setPhase = .resting
            state = .restTimer
            restTimer.start(seconds: restSeconds)
        } else {
            advanceToNextSet()
        }
    }

    func skipRest() {
        restTimer.skip()
        advanceToNextSet()
    }

    func onRestFinished() {
        advanceToNextSet()
    }

    private func advanceToNextSet() {
        let ex = exercises[currentExerciseIndex]
        let nextSetIdx = currentSetIndex + 1

        if nextSetIdx < ex.sets.count {
            // Next set - go straight to performing (stopwatch starts)
            currentSetIndex = nextSetIdx
            setPhase = .performing
            setStopwatch.start()
            state = .loggingSet(
                exerciseIndex: currentExerciseIndex,
                setIndex: nextSetIdx
            )
        } else {
            // Exercise done - advance to next
            advanceToNextExercise()
        }
    }

    private func advanceToNextExercise() {
        let nextIdx = currentExerciseIndex + 1
        if nextIdx < exercises.count {
            currentExerciseIndex = nextIdx
            currentSetIndex = 0
            setPhase = .ready
            state = .active
        } else {
            // All exercises done
            beginFinishing()
        }
    }

    // MARK: - Navigation (skip/jump)

    func jumpToExercise(_ index: Int) {
        guard index < exercises.count else { return }
        restTimer.stop()
        setStopwatch.stop()
        currentExerciseIndex = index
        // Find first incomplete set
        let sets = exercises[index].sets
        currentSetIndex = sets.firstIndex(where: { !$0.isCompleted }) ?? 0
        setPhase = .ready
        state = .active
    }

    func skipExercise() {
        advanceToNextExercise()
    }

    // MARK: - Finish

    func beginFinishing() {
        restTimer.stop()
        setStopwatch.stop()
        state = .finishing
    }

    func cancelFinishing() {
        state = .active
    }

    func saveWorkout() {
        guard let workout, let context = modelContext else { return }

        workout.finishedAt = .now
        workout.durationMinutes = Date.now.timeIntervalSince(workout.startedAt) / 60
        workout.workoutNotes = finishNotes.isEmpty ? nil : finishNotes
        workout.perceivedEffort = finishEffort

        for (eIdx, exerciseState) in exercises.enumerated() {
            let exerciseLog = SDExerciseLog(
                exerciseId: exerciseState.exerciseId,
                exerciseName: exerciseState.name,
                order: eIdx
            )
            exerciseLog.workout = workout

            for setState in exerciseState.sets where setState.isCompleted {
                let setLog = SDSetLog(
                    setNumber: setState.setNumber,
                    setType: setState.type,
                    weightKg: setState.weightKg,
                    reps: setState.reps,
                    rpe: setState.rpe,
                    rir: setState.rir,
                    isPr: false,
                    failed: setState.failed
                )
                setLog.exerciseLog = exerciseLog
            }
        }

        try? context.save()
        state = .saved
    }

    func reset() {
        state = .idle
        exercises = []
        workout = nil
        modelContext = nil
        currentExerciseIndex = 0
        currentSetIndex = 0
        setPhase = .ready
        finishNotes = ""
        finishEffort = nil
        restTimer.stop()
        setStopwatch.stop()
    }
}
