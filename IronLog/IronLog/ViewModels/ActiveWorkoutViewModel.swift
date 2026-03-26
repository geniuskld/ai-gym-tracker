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
    case ready          // before set: slider right=start, left=set weight
    case performing     // during set: slider right=done, left=enter reps
    case enterReps      // quick reps entry after slide-left during performing
    case setWeight      // weight entry from ready phase slide-left
    case resting        // countdown, auto-transitions to performing next set
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

    // MARK: - Resume Workout

    func resumeWorkout(
        sdWorkout: SDWorkout,
        template: SDTemplate,
        context: ModelContext
    ) {
        modelContext = context
        workout = sdWorkout

        // Rebuild exercise states from template
        let sortedGroups = template.groups.sorted { $0.sortOrder < $1.sortOrder }
        let loggedSets = Dictionary(
            grouping: sdWorkout.exercises.flatMap { exLog in
                exLog.sets.map { (exLog.exerciseId, $0) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        exercises = sortedGroups.flatMap { group in
            group.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { exercise in
                    let sortedSets = exercise.prescribedSets
                        .sorted { $0.sortOrder < $1.sortOrder }
                    let logged = loggedSets[exercise.exerciseId] ?? []

                    let setStates = sortedSets.enumerated().map { idx, ps in
                        let matchingLog = logged.first { $0.setNumber == idx + 1 }
                        var ss = SetState(
                            setNumber: idx + 1,
                            type: ps.type,
                            weightKg: matchingLog?.weightKg,
                            reps: matchingLog?.reps,
                            isCompleted: matchingLog != nil,
                            failed: matchingLog?.failed ?? false,
                            prescribedRepsMin: ps.repsMin,
                            prescribedRepsMax: ps.repsMax,
                            prescribedRir: ps.rir,
                            prescribedWeightPercentDrop: ps.weightPercentDrop
                        )
                        return ss
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

        // Find first incomplete exercise/set
        for (eIdx, ex) in exercises.enumerated() {
            if let sIdx = ex.sets.firstIndex(where: { !$0.isCompleted }) {
                currentExerciseIndex = eIdx
                currentSetIndex = sIdx
                setPhase = .ready
                state = .active
                return
            }
        }

        // All sets done, go to finishing
        currentExerciseIndex = exercises.count - 1
        currentSetIndex = 0
        state = .active
        beginFinishing()
    }

    // MARK: - Set Flow

    // Ready phase: slide right = start set with current weight
    func readySlideRight() {
        if let last = lastCompletedWeight {
            exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = last
        }
        beginPerforming()
    }

    // Ready phase: slide left = set weight before starting
    func readySlideLeft() {
        setPhase = .setWeight
    }

    // Confirm weight and start performing
    func confirmWeightAndStart(_ kg: Double) {
        exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = kg
        beginPerforming()
    }

    private func beginPerforming() {
        setPhase = .performing
        setStopwatch.start()
        state = .loggingSet(
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex
        )
    }

    // Performing phase: slide right = done (auto reps from prescribed)
    func performingSlideRight() {
        setStopwatch.stop()
        let reps = exercises[currentExerciseIndex].sets[currentSetIndex]
            .prescribedRepsMin ?? 10
        completeCurrentSet(reps: reps)
    }

    // Performing phase: slide left = enter reps manually
    func performingSlideLeft() {
        setStopwatch.stop()
        setPhase = .enterReps
    }

    func confirmReps(_ count: Int) {
        completeCurrentSet(reps: count)
    }

    private func completeCurrentSet(reps: Int) {
        guard currentExerciseIndex < exercises.count,
              currentSetIndex < exercises[currentExerciseIndex].sets.count
        else { return }

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
