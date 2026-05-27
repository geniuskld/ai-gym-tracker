import XCTest
import SwiftData
@testable import IronLog

@MainActor
final class MyoRepsFlowTests: XCTestCase {

    func testTimerTapStartsStraightSetWithoutExtraReadyTap() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildStraightTemplate(in: context)
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        vm.readySlideRight()
        vm.confirmPerforming(weight: 20, reps: 12)

        XCTAssertEqual(vm.state, .restTimer)
        XCTAssertEqual(vm.setPhase, .resting)
        XCTAssertTrue(vm.restStartsNextSetImmediately)
        XCTAssertEqual(vm.currentSetIndex, 1)
        XCTAssertEqual(vm.currentSet?.type, "working")

        vm.onRestFinished()

        XCTAssertEqual(vm.setPhase, .performing)
        XCTAssertEqual(vm.state, .loggingSet(exerciseIndex: 0, setIndex: 1))
        XCTAssertTrue(vm.setStopwatch.isRunning)
        XCTAssertFalse(vm.flowLockWeight)
    }

    func testTimerTapStartsMiniSetWithoutExtraReadyTap() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildMyoTemplate(in: context)
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        vm.readySlideRight()
        vm.confirmPerforming(weight: 20, reps: 14)

        XCTAssertEqual(vm.state, .restTimer)
        XCTAssertEqual(vm.setPhase, .resting)
        XCTAssertTrue(vm.restStartsNextSetImmediately)
        XCTAssertEqual(vm.currentSetIndex, 1)
        XCTAssertEqual(vm.currentSet?.type, "myo_mini")

        vm.onRestFinished()

        XCTAssertEqual(vm.setPhase, .performing)
        XCTAssertEqual(vm.state, .loggingSet(exerciseIndex: 0, setIndex: 1))
        XCTAssertTrue(vm.setStopwatch.isRunning)
        XCTAssertTrue(vm.flowLockWeight)
    }

    func testRemainingTimeIsHiddenWithoutHistoryOrLiveData() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildStraightTemplate(in: context)
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        XCTAssertNil(vm.remainingWorkoutMinutesText)
    }

    func testRemainingTimeUsesPreviousCompletedTemplateWorkout() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildStraightTemplate(in: context)
        Self.insertHistoricalWorkout(
            templateId: template.templateId,
            templateName: template.name,
            durationMinutes: 90,
            setCount: 2,
            into: context
        )
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        XCTAssertEqual(vm.remainingWorkoutMinutesText, "~90 min left")
    }

    func testRemainingTimeStaysAnchoredToHistoricalDurationEarlyInWorkout() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildStraightTemplate(in: context, setCount: 8)
        Self.insertHistoricalWorkout(
            templateId: template.templateId,
            templateName: template.name,
            durationMinutes: 95,
            setCount: 8,
            into: context
        )
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)
        vm.workout?.startedAt = Date.now.addingTimeInterval(-8 * 60)

        vm.readySlideRight()
        vm.confirmPerforming(weight: 20, reps: 12)
        let loggedSet = vm.workout?.exercises.first?.sets.first
        loggedSet?.setDurationSeconds = 60
        loggedSet?.restSecondsAfter = 300

        XCTAssertEqual(vm.remainingWorkoutMinutesText, "~87 min left")
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
            SDCyclingPlan.self, SDCyclingTemplate.self, SDCyclingSegment.self,
            SDCyclingWorkout.self, SDCyclingSegmentLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func buildStraightTemplate(
        in ctx: ModelContext,
        setCount: Int = 2
    ) -> SDTemplate {
        let plan = SDPlan(
            planType: "strength",
            planId: "test-straight",
            planName: "Test Straight",
            planVersion: 1,
            createdAt: .now
        )
        ctx.insert(plan)

        let template = SDTemplate(
            templateId: "day-straight",
            name: "Straight",
            sortOrder: 0
        )
        template.plan = plan

        let group = SDExerciseGroup(name: "Chest", sortOrder: 0)
        group.template = template

        let exercise = SDExercise(
            exerciseId: "straight-1",
            name: "Chest press",
            bodyPart: "chest",
            restSeconds: 90,
            technique: "straight",
            sortOrder: 0
        )
        exercise.group = group

        for index in 0..<setCount {
            let set = SDPrescribedSet(
                type: "working",
                reps: 12,
                weightKg: 20,
                rir: 1,
                sortOrder: index
            )
            set.exercise = exercise
        }

        return template
    }

    private static func buildMyoTemplate(in ctx: ModelContext) -> SDTemplate {
        let plan = SDPlan(
            planType: "strength",
            planId: "test-myo",
            planName: "Test Myo",
            planVersion: 1,
            createdAt: .now
        )
        ctx.insert(plan)

        let template = SDTemplate(
            templateId: "day-myo",
            name: "Myo",
            sortOrder: 0
        )
        template.plan = plan

        let group = SDExerciseGroup(name: "Legs", sortOrder: 0)
        group.template = template

        let exercise = SDExercise(
            exerciseId: "myo-1",
            name: "Leg curl",
            bodyPart: "legs",
            restSeconds: 90,
            technique: "myo_reps",
            sortOrder: 0,
            maxMiniSets: 5
        )
        exercise.group = group

        let activation = SDPrescribedSet(
            type: "working",
            reps: 14,
            weightKg: 20,
            rir: 1,
            sortOrder: 0
        )
        activation.exercise = exercise

        return template
    }

    private static func insertHistoricalWorkout(
        templateId: String,
        templateName: String,
        durationMinutes: Double,
        setCount: Int,
        into context: ModelContext
    ) {
        let workout = SDWorkout(
            templateId: templateId,
            templateName: templateName,
            planType: "strength",
            startedAt: Date.now.addingTimeInterval(-7200)
        )
        workout.finishedAt = Date.now.addingTimeInterval(-1800)
        workout.durationMinutes = durationMinutes
        context.insert(workout)

        let exerciseLog = SDExerciseLog(
            exerciseId: "straight-1",
            exerciseName: "Chest press",
            bodyPart: "chest",
            order: 0,
            technique: "straight"
        )
        exerciseLog.workout = workout

        for index in 0..<setCount {
            let setLog = SDSetLog(
                setNumber: index + 1,
                setType: "working",
                weightKg: 20,
                reps: 12
            )
            setLog.exerciseLog = exerciseLog
        }
    }
}
