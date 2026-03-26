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

    // Prescribed hints (read-only, from plan)
    var prescribedRepsMin: Int?
    var prescribedRepsMax: Int?
    var prescribedRir: Int?
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

    var state: State = .idle
    var exercises: [ExerciseState] = []
    var restTimer = RestTimerService()
    var finishNotes: String = ""
    var finishEffort: Int?

    private var workout: SDWorkout?
    private var templateId: String = ""
    private var templateName: String = ""
    private var modelContext: ModelContext?

    // MARK: - Start

    func startWorkout(
        template: SDTemplate,
        context: ModelContext
    ) {
        modelContext = context
        templateId = template.templateId
        templateName = template.name

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
                    let sortedSets = exercise.prescribedSets.sorted { $0.sortOrder < $1.sortOrder }
                    let setStates = sortedSets.enumerated().map { idx, ps in
                        SetState(
                            setNumber: idx + 1,
                            type: ps.type,
                            prescribedRepsMin: ps.repsMin,
                            prescribedRepsMax: ps.repsMax,
                            prescribedRir: ps.rir
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

        state = .active
    }

    // MARK: - Logging

    func beginLoggingSet(
        exerciseIndex: Int,
        setIndex: Int
    ) {
        state = .loggingSet(
            exerciseIndex: exerciseIndex,
            setIndex: setIndex
        )
    }

    func completeSet(
        exerciseIndex: Int,
        setIndex: Int
    ) {
        guard exerciseIndex < exercises.count,
              setIndex < exercises[exerciseIndex].sets.count else { return }

        exercises[exerciseIndex].sets[setIndex].isCompleted = true

        let restSeconds = exercises[exerciseIndex].restSeconds
        if restSeconds > 0 {
            state = .restTimer
            restTimer.start(seconds: restSeconds)
        } else {
            state = .active
        }
    }

    func toggleFailed(
        exerciseIndex: Int,
        setIndex: Int
    ) {
        guard exerciseIndex < exercises.count,
              setIndex < exercises[exerciseIndex].sets.count else { return }
        exercises[exerciseIndex].sets[setIndex].failed.toggle()
    }

    func addSet(exerciseIndex: Int) {
        guard exerciseIndex < exercises.count else { return }
        let currentCount = exercises[exerciseIndex].sets.count
        let newSet = SetState(
            setNumber: currentCount + 1,
            type: "working"
        )
        exercises[exerciseIndex].sets.append(newSet)
    }

    func removeSet(
        exerciseIndex: Int,
        setIndex: Int
    ) {
        guard exerciseIndex < exercises.count,
              setIndex < exercises[exerciseIndex].sets.count,
              exercises[exerciseIndex].sets.count > 1 else { return }
        exercises[exerciseIndex].sets.remove(at: setIndex)
        // Renumber
        for i in exercises[exerciseIndex].sets.indices {
            exercises[exerciseIndex].sets[i].setNumber = i + 1
        }
    }

    // MARK: - Timer

    func skipTimer() {
        restTimer.skip()
        state = .active
    }

    func onTimerFinished() {
        state = .active
    }

    // MARK: - Finish

    func beginFinishing() {
        state = .finishing
    }

    func cancelFinishing() {
        state = .active
    }

    func saveWorkout() {
        guard let workout, let context = modelContext else { return }

        workout.finishedAt = .now
        if let started = Optional(workout.startedAt) {
            workout.durationMinutes = Date.now.timeIntervalSince(started) / 60
        }
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
        finishNotes = ""
        finishEffort = nil
        restTimer.stop()
    }

    // MARK: - Computed

    var isActive: Bool {
        switch state {
        case .active, .loggingSet, .restTimer:
            return true
        default:
            return false
        }
    }

    var completedSetsCount: Int {
        exercises.reduce(0) { total, ex in
            total + ex.sets.filter(\.isCompleted).count
        }
    }

    var totalSetsCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}
