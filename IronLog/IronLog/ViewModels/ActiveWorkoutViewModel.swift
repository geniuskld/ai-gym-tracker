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
    var prescribedReps: Int?
    var prescribedWeightKg: Double?
    var prescribedRir: Int?
    var prescribedWeightPercentDrop: Double?
}

struct ExerciseState: Identifiable {
    let id = UUID()
    let exerciseId: String
    let catalogId: String?
    let name: String
    let bodyPart: String
    let equipment: String?
    let technique: String
    let supersetWith: String?
    let restSeconds: Int
    let tempo: String?
    let notes: String?
    let stretchFocus: Bool
    let maxMiniSets: Int?
    var sets: [SetState]
    var supersetPartnerIndex: Int? = nil
}

// MARK: - Phases within a set

enum SetPhase: Equatable {
    case ready          // before set: shows weight preview + Start
    case performing     // during set: timer + weight/reps adjustable + Done
    case resting        // countdown, auto-transitions to next step
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
    var skipHealthKit = false
    var persistenceErrorMessage: String?

    /// Current technique flow driving the workout progression
    private(set) var currentFlow: (any TechniqueFlow)?

    /// Instruction text from the current technique flow
    var flowInstruction: String = ""
    /// Whether the current step locks weight (drop/myo mini)
    var flowLockWeight: Bool = false

    private(set) var workout: SDWorkout?
    private var modelContext: ModelContext?
    private var lastSetCompletedAt: Date?
    private var stateBeforeFinishing: State?

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
        weightForExercise(at: currentExerciseIndex)
    }

    /// Weight for a specific exercise: last working weight, or prescribed, or nil
    func weightForExercise(at exerciseIdx: Int) -> Double? {
        guard exerciseIdx < exercises.count else { return nil }
        let ex = exercises[exerciseIdx]
        // 1. Last completed working weight (not from drop sets)
        if let w = lastWorkingWeight(ex) { return w }
        // 2. Any completed weight
        if let w = lastCompletedWeightAny(ex) { return w }
        // 3. Current set's pre-filled weight
        let setIdx = currentSetIndex < ex.sets.count ? currentSetIndex : 0
        if let w = ex.sets[setIdx].weightKg { return w }
        // 4. Prescribed weight from plan
        if let pw = ex.sets[setIdx].prescribedWeightKg {
            return pw
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

    var isDynamicFlow: Bool {
        currentFlow?.supportsDynamicSets ?? false
    }

    /// True when resting before advancing to the next exercise (not next set)
    var isRestBeforeNextExercise: Bool {
        pendingAdvanceToNextExercise
    }

    /// Name of the next exercise (if any)
    var nextExerciseName: String? {
        let nextIdx = currentExerciseIndex + 1
        guard nextIdx < exercises.count else { return nil }
        return exercises[nextIdx].name
    }

    // MARK: - Start Workout

    func startWorkout(
        template: SDTemplate,
        context: ModelContext
    ) {
        modelContext = context

        let sdWorkout = SDWorkout(
            templateId: template.templateId,
            templateName: template.name,
            planType: template.plan?.planType,
            planId: template.plan?.planId,
            planName: template.plan?.planName,
            planVersion: template.plan?.planVersion
        )
        context.insert(sdWorkout)
        _ = saveContext(context, action: "start workout")
        workout = sdWorkout

        buildExercises(from: template, loggedSets: [:])
        linkSupersetPartners()
        currentExerciseIndex = 0
        currentSetIndex = 0
        setPhase = .ready
        state = .active
        activateFlowForCurrentExercise()

        // Mirror to Apple Watch
        WorkoutSessionManager.shared.startMirroring()
    }

    // MARK: - Resume Workout

    func resumeWorkout(
        sdWorkout: SDWorkout,
        template: SDTemplate,
        context: ModelContext
    ) {
        modelContext = context
        workout = sdWorkout

        let loggedSets = Dictionary(
            grouping: sdWorkout.exercises.flatMap { exLog in
                exLog.sets.map { (exLog.exerciseId, $0) }
            },
            by: \.0
        ).mapValues { $0.map(\.1) }

        buildExercises(from: template, loggedSets: loggedSets)
        linkSupersetPartners()

        // Find first incomplete exercise/set
        for (eIdx, ex) in exercises.enumerated() {
            if let sIdx = ex.sets.firstIndex(where: { !$0.isCompleted }) {
                currentExerciseIndex = eIdx
                currentSetIndex = sIdx
                setPhase = .ready
                state = .active
                activateFlowForCurrentExercise()
                return
            }
        }

        // All sets done
        currentExerciseIndex = exercises.count - 1
        currentSetIndex = 0
        state = .active
        beginFinishing()
    }

    private func buildExercises(
        from template: SDTemplate,
        loggedSets: [String: [SDSetLog]]
    ) {
        let sortedGroups = template.groups.sorted { $0.sortOrder < $1.sortOrder }
        exercises = sortedGroups.flatMap { group in
            group.exercises
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { exercise in
                    let sortedSets = exercise.prescribedSets
                        .sorted { $0.sortOrder < $1.sortOrder }
                    let logged = loggedSets[exercise.exerciseId] ?? []

                    let setStates = sortedSets.enumerated().map { idx, ps in
                        let matchingLog = logged.first { $0.setNumber == idx + 1 }
                        return SetState(
                            setNumber: idx + 1,
                            type: ps.type,
                            weightKg: matchingLog?.weightKg ?? ps.weightKg,
                            reps: matchingLog?.reps,
                            isCompleted: matchingLog != nil,
                            failed: matchingLog?.failed ?? false,
                            prescribedReps: ps.reps,
                            prescribedWeightKg: ps.weightKg,
                            prescribedRir: ps.rir,
                            prescribedWeightPercentDrop: ps.weightPercentDrop
                        )
                    }
                    return ExerciseState(
                        exerciseId: exercise.exerciseId,
                        catalogId: exercise.catalogId,
                        name: exercise.name,
                        bodyPart: exercise.bodyPart,
                        equipment: exercise.equipment,
                        technique: exercise.technique,
                        supersetWith: exercise.supersetWith,
                        restSeconds: exercise.restSeconds,
                        tempo: exercise.tempo,
                        notes: exercise.notes,
                        stretchFocus: exercise.stretchFocus,
                        maxMiniSets: exercise.maxMiniSets,
                        sets: setStates
                    )
                }
        }
    }

    private func linkSupersetPartners() {
        for i in exercises.indices {
            if let partnerId = exercises[i].supersetWith,
               let partnerIdx = exercises.firstIndex(where: { $0.exerciseId == partnerId }) {
                exercises[i].supersetPartnerIndex = partnerIdx
            }
        }
    }

    // MARK: - Flow Management

    /// Creates and activates the TechniqueFlow for the current exercise.
    private func activateFlowForCurrentExercise() {
        currentFlow = TechniqueFlowFactory.makeFlow(
            for: currentExerciseIndex,
            exercises: exercises
        )
        updateFlowInstruction(
            completedExerciseIndex: nil,
            completedSetIndex: nil,
            completedReps: nil
        )
    }

    private func updateFlowInstruction(
        completedExerciseIndex: Int?,
        completedSetIndex: Int?,
        completedReps: Int?
    ) {
        if let step = currentFlow?.nextStep(
            exercises: exercises,
            completedExerciseIndex: completedExerciseIndex,
            completedSetIndex: completedSetIndex,
            completedReps: completedReps
        ) {
            flowInstruction = step.instruction
            flowLockWeight = step.lockWeight
            // Apply suggested weight if the set has no weight yet
            if let w = step.suggestedWeightKg,
               step.exerciseIndex < exercises.count,
               step.setIndex < exercises[step.exerciseIndex].sets.count,
               exercises[step.exerciseIndex].sets[step.setIndex].weightKg == nil {
                exercises[step.exerciseIndex].sets[step.setIndex].weightKg = w
            }
        }
    }

    // MARK: - Set Flow

    // Ready phase: slide right = start set with current weight
    func readySlideRight() {
        let set = exercises[currentExerciseIndex].sets[currentSetIndex]
        // Only apply last weight if this set has no prescribed weight
        if set.weightKg == nil, let last = lastCompletedWeight {
            exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = last
        }
        beginPerforming()
    }

    private func beginPerforming() {
        // Record actual rest duration on previous set
        if let completedAt = lastSetCompletedAt {
            let actualRest = Int(Date().timeIntervalSince(completedAt))
            persistRestDuration(actualRest)
        }

        setPhase = .performing
        setStopwatch.start()
        state = .loggingSet(
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex
        )

        // Update Live Activity to performing phase
        RestTimerActivityManager.shared.startPerforming(
            exerciseName: currentExercise?.name ?? "",
            weightKg: exercises[currentExerciseIndex].sets[currentSetIndex].weightKg
        )
    }

    // Performing phase: confirm weight + reps and finish set
    func confirmPerforming(weight: Double, reps: Int) {
        setStopwatch.stop()
        exercises[currentExerciseIndex].sets[currentSetIndex].weightKg = weight
        completeCurrentSet(reps: reps)
    }

    // MARK: - Core: Complete Set + Flow-Driven Progression

    private func completeCurrentSet(reps: Int) {
        guard currentExerciseIndex < exercises.count,
              currentSetIndex < exercises[currentExerciseIndex].sets.count
        else { return }

        // Mark set as completed
        exercises[currentExerciseIndex].sets[currentSetIndex].reps = reps
        exercises[currentExerciseIndex].sets[currentSetIndex].isCompleted = true
        exercises[currentExerciseIndex].sets[currentSetIndex].setDurationSeconds =
            setStopwatch.elapsedSeconds

        lastSetCompletedAt = Date()
        persistCompletedSet()

        let completedExIdx = currentExerciseIndex
        let completedSetIdx = currentSetIndex

        // Ask flow for next step
        guard let flow = currentFlow else {
            startRest(seconds: exercises[currentExerciseIndex].restSeconds)
            return
        }

        guard let nextStep = flow.nextStep(
            exercises: exercises,
            completedExerciseIndex: completedExIdx,
            completedSetIndex: completedSetIdx,
            completedReps: reps
        ) else {
            // Flow complete -- rest then advance to next exercise
            flowInstruction = ""
            flowLockWeight = false
            let restSeconds = exercises[completedExIdx].restSeconds
            pendingAdvanceToNextExercise = true
            startRest(seconds: restSeconds)
            return
        }

        // Dynamic set insertion (myo-reps mini-sets)
        if flow.supportsDynamicSets
            && nextStep.setIndex >= exercises[nextStep.exerciseIndex].sets.count {
            let newSet = SetState(
                setNumber: nextStep.setIndex + 1,
                type: "myo_mini",
                prescribedReps: nextStep.prescribedReps,
                prescribedRir: nil,
                prescribedWeightPercentDrop: nil
            )
            exercises[nextStep.exerciseIndex].sets.append(newSet)
        }

        // Apply suggested weight
        if let w = nextStep.suggestedWeightKg {
            exercises[nextStep.exerciseIndex].sets[nextStep.setIndex].weightKg = w
        }

        // Update current position
        currentExerciseIndex = nextStep.exerciseIndex
        currentSetIndex = nextStep.setIndex
        flowInstruction = nextStep.instruction

        // Rest or go directly
        if let rest = nextStep.restSeconds, rest > 0 {
            pendingAdvanceToNextExercise = false
            startRest(seconds: rest)
        } else {
            setPhase = .ready
            state = .active
        }
    }

    /// Flag: after rest finishes, should we advance to next exercise?
    private var pendingAdvanceToNextExercise = false

    private func startRest(seconds: Int) {
        if seconds > 0 {
            setPhase = .resting
            state = .restTimer

            // Provide context for Live Activity
            restTimer.liveActivityExerciseName = currentExercise?.name ?? ""
            restTimer.liveActivityNextLabel = flowInstruction.isEmpty
                ? "SET \(currentSetIndex + 1)"
                : flowInstruction

            restTimer.start(seconds: seconds)
        } else {
            onRestComplete()
        }
    }

    func skipRest() {
        restTimer.stop()
        onRestComplete()
    }

    func onRestFinished() {
        restTimer.stop()
        onRestComplete()
    }

    private func onRestComplete() {
        if pendingAdvanceToNextExercise {
            pendingAdvanceToNextExercise = false
            applyPendingRatingAndAdvance()
        } else {
            // Flow already set currentExerciseIndex/currentSetIndex
            setPhase = .ready
            state = .active
        }
    }

    func finishExercise() {
        // Trigger rest-before-next-exercise so the user can rate during rest
        pendingAdvanceToNextExercise = true
        let restSeconds = currentExercise?.restSeconds ?? 60
        startRest(seconds: restSeconds)
    }

    /// Pending rating set by the user during rest. Applied on rest completion.
    var pendingRating: Int?

    /// User taps Heavy/OK/Easy during rest. Toggles off if same value pressed again.
    func setPendingRating(_ rating: Int?) {
        if pendingRating == rating {
            pendingRating = nil
        } else {
            pendingRating = rating
        }
    }

    private func applyPendingRatingAndAdvance() {
        if let rating = pendingRating, let workout {
            let exId = exercises[currentExerciseIndex].exerciseId
            if let exLog = workout.exercises.first(where: { $0.exerciseId == exId }) {
                exLog.exerciseRating = rating
                if let context = modelContext {
                    _ = saveContext(context, action: "save exercise rating")
                }
            }
        }
        pendingRating = nil
        advanceToNextExercise()
    }

    private func advanceToNextExercise() {
        // Find next exercise not covered by the current flow
        let coveredIndices = Set(currentFlow?.exerciseIndices ?? [])
        var nextIdx = (coveredIndices.max() ?? currentExerciseIndex) + 1

        // Skip superset partners that were already processed
        while nextIdx < exercises.count {
            let ex = exercises[nextIdx]
            if ex.technique == "superset",
               let partnerIdx = ex.supersetPartnerIndex,
               partnerIdx < nextIdx {
                // This is the "junior" partner -- skip, it was handled by the flow
                nextIdx += 1
            } else {
                break
            }
        }

        if nextIdx < exercises.count {
            currentExerciseIndex = nextIdx
            currentSetIndex = 0
            activateFlowForCurrentExercise()

            // Apply initial weight from flow
            if let step = currentFlow?.nextStep(
                exercises: exercises,
                completedExerciseIndex: nil,
                completedSetIndex: nil,
                completedReps: nil
            ) {
                currentExerciseIndex = step.exerciseIndex
                currentSetIndex = step.setIndex
                if let w = step.suggestedWeightKg {
                    exercises[step.exerciseIndex].sets[step.setIndex].weightKg = w
                }
                flowInstruction = step.instruction
            }

            setPhase = .ready
            state = .active
        } else {
            beginFinishing()
        }
    }

    // MARK: - Navigation (skip/jump)

    func jumpToExercise(_ index: Int) {
        guard index < exercises.count else { return }
        restTimer.stop()
        setStopwatch.stop()
        pendingAdvanceToNextExercise = false
        currentExerciseIndex = index
        let sets = exercises[index].sets
        currentSetIndex = sets.firstIndex(where: { !$0.isCompleted }) ?? 0
        activateFlowForCurrentExercise()
        setPhase = .ready
        state = .active
    }

    func skipExercise() {
        advanceToNextExercise()
    }

    // MARK: - Exercise Notes

    func saveExerciseNote(
        _ note: String,
        forExerciseAt index: Int
    ) {
        guard let workout, let context = modelContext else { return }
        let exState = exercises[index]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let exLog = workout.exercises.first(where: {
            $0.exerciseId == exState.exerciseId
        }) {
            exLog.exerciseNotes = trimmed.isEmpty ? nil : trimmed
        } else {
            let newLog = SDExerciseLog(
                exerciseId: exState.exerciseId,
                catalogId: exState.catalogId,
                exerciseName: exState.name,
                bodyPart: exState.bodyPart,
                order: index,
                exerciseNotes: trimmed.isEmpty ? nil : trimmed
            )
            newLog.workout = workout
        }
        _ = saveContext(context, action: "save exercise note")
    }

    func exerciseNote(at index: Int) -> String {
        guard let workout else { return "" }
        let exId = exercises[index].exerciseId
        return workout.exercises
            .first { $0.exerciseId == exId }?
            .exerciseNotes ?? ""
    }

    // MARK: - Finish

    func beginFinishing() {
        if case .finishing = state {
            return
        }
        stateBeforeFinishing = state
        state = .finishing
    }

    func cancelFinishing() {
        state = stateBeforeFinishing ?? .active
        stateBeforeFinishing = nil
    }

    // MARK: - Incremental Persistence

    private func persistCompletedSet() {
        guard let workout, let context = modelContext else { return }

        let exState = exercises[currentExerciseIndex]
        let setState = exState.sets[currentSetIndex]

        let exerciseLog: SDExerciseLog
        if let existing = workout.exercises.first(where: {
            $0.exerciseId == exState.exerciseId
        }) {
            exerciseLog = existing
        } else {
            let newLog = SDExerciseLog(
                exerciseId: exState.exerciseId,
                catalogId: exState.catalogId,
                exerciseName: exState.name,
                bodyPart: exState.bodyPart,
                order: currentExerciseIndex
            )
            newLog.workout = workout
            exerciseLog = newLog
        }

        if let oldSet = exerciseLog.sets.first(where: {
            $0.setNumber == setState.setNumber
        }) {
            context.delete(oldSet)
        }

        let setLog = SDSetLog(
            setNumber: setState.setNumber,
            setType: setState.type,
            weightKg: setState.weightKg,
            reps: setState.reps,
            rpe: setState.rpe,
            rir: setState.rir,
            setDurationSeconds: setState.setDurationSeconds,
            isPr: false,
            failed: setState.failed
        )
        setLog.exerciseLog = exerciseLog

        _ = saveContext(context, action: "save completed set")
    }

    private func persistRestDuration(_ seconds: Int) {
        guard let workout, let context = modelContext else { return }

        let exState = exercises[max(0, currentExerciseIndex)]
        let prevSetIdx = currentSetIndex - 1

        if prevSetIdx >= 0 {
            if let exLog = workout.exercises.first(where: {
                $0.exerciseId == exState.exerciseId
            }),
               let setLog = exLog.sets.first(where: {
                   $0.setNumber == prevSetIdx + 1
                }) {
                setLog.restSecondsAfter = seconds
                _ = saveContext(context, action: "save rest duration")
            }
        } else if currentExerciseIndex > 0 {
            let prevEx = exercises[currentExerciseIndex - 1]
            if let exLog = workout.exercises.first(where: {
                $0.exerciseId == prevEx.exerciseId
            }),
               let lastSet = exLog.sets.sorted(by: {
                   $0.setNumber < $1.setNumber
               }).last {
                lastSet.restSecondsAfter = seconds
                _ = saveContext(context, action: "save rest duration")
            }
        }
    }

    func saveWorkout() {
        guard let workout, let context = modelContext else { return }

        let endDate = Date.now
        workout.finishedAt = endDate
        workout.durationMinutes = endDate.timeIntervalSince(workout.startedAt) / 60
        workout.workoutNotes = finishNotes.isEmpty ? nil : finishNotes
        workout.perceivedEffort = finishEffort

        guard saveContext(context, action: "save workout") else { return }

        restTimer.stop()
        setStopwatch.stop()

        // Stop Apple Watch mirroring
        WorkoutSessionManager.shared.stopMirroring()

        // Save to HealthKit
        if !skipHealthKit {
            let totalVolume = workout.exercises.flatMap(\.sets).reduce(0.0) { sum, set in
                let w = set.weightKg ?? 0
                let r = Double(set.reps ?? 0)
                return sum + w * r
            }
            let totalSets = workout.exercises.flatMap(\.sets).count

            HealthKitManager.shared.saveWorkout(
                startDate: workout.startedAt,
                endDate: endDate,
                totalVolume: totalVolume,
                totalSets: totalSets,
                templateName: workout.templateName,
                planName: workout.planName
            )
        }

        // Upload log to sync server (fire-and-forget)
        if SyncService.isConfigured,
           SyncService.isAuthenticated,
           workout.syncedAt == nil {
            Task {
                await WorkoutSyncService.uploadStrength(
                    workout,
                    context: context,
                    force: true
                )
            }
        }

        stateBeforeFinishing = nil
        state = .saved
    }

    @discardableResult
    private func saveContext(
        _ context: ModelContext,
        action: String
    ) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            persistenceErrorMessage = "Could not \(action): \(error.localizedDescription)"
            return false
        }
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
        persistenceErrorMessage = nil
        stateBeforeFinishing = nil
        currentFlow = nil
        flowInstruction = ""
        flowLockWeight = false
        pendingAdvanceToNextExercise = false
        restTimer.stop()
        setStopwatch.stop()
    }
}
