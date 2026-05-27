import XCTest
import SwiftData
@testable import IronLog

/// Plan v12 introduces a new layout: ONE exercise group can contain
/// multiple INDEPENDENT superset pairs (e.g. day-A "Грудь+Спина" has
/// `a4 <-> a6` and `a5 <-> a9` back-to-back). Verify the routing logic
/// in `ActiveWorkoutViewModel` + `TechniqueFlowFactory` correctly
/// visits ALL exercises and completes ALL sets, not just the first pair.
@MainActor
final class MultipleSupersetPairsTests: XCTestCase {

    /// v12 day-A layout (techniques simplified to `straight` for non-superset
    /// exercises -- the bug we are testing is in superset routing, which is
    /// independent of how the other techniques walk their own sets).
    func testTwoAdjacentSupersetPairsBothExecuteFully() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildTemplate(in: context)
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        XCTAssertEqual(vm.exercises.count, 9, "9 exercises expected after flatten")

        try await driveToCompletion(vm: vm, maxIterations: 1500)

        // Sanity: every exercise had every set marked complete.
        for ex in vm.exercises {
            let pattern = ex.sets.map { $0.isCompleted ? "v" : "x" }.joined()
            XCTAssertTrue(
                ex.sets.allSatisfy(\.isCompleted),
                "Exercise \(ex.exerciseId) (\(ex.name)) sets: [\(pattern)]"
            )
        }

        XCTAssertTrue(
            [.finishing, .saved].contains(vm.state),
            "VM should reach finishing or saved, was \(vm.state)"
        )

        let workout = try XCTUnwrap(vm.workout)
        let exported = WorkoutExportService.workoutToJSON(workout)
        let pairEvents = (exported.setEvents ?? [])
            .filter { ["a4", "a6"].contains($0.exerciseId) }

        XCTAssertEqual(
            pairEvents.map { "\($0.exerciseId)#\($0.setNumber)" },
            ["a4#1", "a6#1", "a4#2", "a6#2", "a4#3", "a6#3"],
            "Superset pair should be exported in actual A/B chronological order"
        )
        XCTAssertTrue(pairEvents.allSatisfy { $0.supersetPairId == "a4+a6" })
    }

    func testSupersetRestDurationAttachesToLastChronologicalSet() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let template = Self.buildTwoExerciseSupersetTemplate(in: context)
        try context.save()

        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(template: template, context: context)

        vm.readySlideRight()
        vm.confirmPerforming(weight: 10, reps: 12)

        vm.readySlideRight()
        vm.confirmPerforming(weight: 10, reps: 12)

        XCTAssertEqual(vm.state, .restTimer)
        vm.skipRest()
        XCTAssertEqual(vm.state, .active)
        vm.readySlideRight()

        let workout = try XCTUnwrap(vm.workout)
        let press = try XCTUnwrap(
            workout.exercises.first { $0.exerciseId == "press" }
        )
        let row = try XCTUnwrap(
            workout.exercises.first { $0.exerciseId == "row" }
        )
        let pressSet1 = try XCTUnwrap(
            press.sets.first { $0.setNumber == 1 }
        )
        let rowSet1 = try XCTUnwrap(
            row.sets.first { $0.setNumber == 1 }
        )

        XCTAssertEqual(pressSet1.sequenceIndex, 1)
        XCTAssertEqual(rowSet1.sequenceIndex, 2)
        XCTAssertNotNil(
            pressSet1.restSecondsAfter,
            "Transition from first superset exercise should be stored on that set"
        )
        XCTAssertNotNil(
            rowSet1.restSecondsAfter,
            "Between-round rest should be stored on the second exercise's set"
        )
    }

    // MARK: - Driver

    /// Walks the VM through any state by responding to whatever phase it
    /// is currently in. Caps iterations to detect infinite loops.
    private func driveToCompletion(
        vm: ActiveWorkoutViewModel,
        maxIterations: Int
    ) async throws {
        for _ in 0..<maxIterations {
            switch vm.state {
            case .active:
                if vm.setPhase == .ready {
                    vm.readySlideRight()
                } else if vm.setPhase == .performing {
                    vm.confirmPerforming(weight: 10, reps: 12)
                } else if vm.setPhase == .resting {
                    vm.skipRest()
                }
            case .loggingSet:
                // Performing phase exposed via state machine.
                vm.confirmPerforming(weight: 10, reps: 12)
            case .restTimer:
                vm.skipRest()
            case .finishing, .saved:
                return
            case .idle:
                XCTFail("VM became .idle mid-workout")
                return
            }

            // Let any async hops settle.
            await Task.yield()
        }
        XCTFail("Workout did not complete within \(maxIterations) iterations")
    }

    // MARK: - Test data builders

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

    /// Builds a SDTemplate that mirrors v12 day-A's structure:
    ///
    ///   group "Legs":     a1, a2, a3              (3 single-tech exercises)
    ///   group "Antagon":  a4 <-> a6, a5 <-> a9    (TWO superset pairs)
    ///   group "Arms":     a7 <-> a8               (one superset pair)
    ///
    /// Total = 9 exercises. The non-superset exercises use `straight` so
    /// the test stays focused on superset routing.
    private static func buildTemplate(in ctx: ModelContext) -> SDTemplate {
        let plan = SDPlan(
            planType: "strength",
            planId: "test-multi-superset",
            planName: "Test",
            planVersion: 1,
            createdAt: .now
        )
        ctx.insert(plan)

        let template = SDTemplate(
            templateId: "day-a",
            name: "День A",
            sortOrder: 0
        )
        template.plan = plan

        // group: legs (3 straight exercises)
        let legs = SDExerciseGroup(name: "Ноги", sortOrder: 0)
        legs.template = template
        addStraight(in: legs, id: "a1", name: "Жим ногами", bp: "legs", sortOrder: 0, sets: 3)
        addStraight(in: legs, id: "a2", name: "Разгибание", bp: "legs", sortOrder: 1, sets: 3)
        addStraight(in: legs, id: "a3", name: "Сгибание",   bp: "legs", sortOrder: 2, sets: 3)

        // group: chest+back antagonist supersets (a4<->a6, a5<->a9)
        let antag = SDExerciseGroup(name: "Грудь+Спина", sortOrder: 1)
        antag.template = template
        addSuperset(in: antag, id: "a4", with: "a6", name: "Жим Matrix",   bp: "chest", sortOrder: 0, sets: 3)
        addSuperset(in: antag, id: "a6", with: "a4", name: "Тяга блока",   bp: "back",  sortOrder: 1, sets: 3)
        addSuperset(in: antag, id: "a5", with: "a9", name: "Fly",          bp: "chest", sortOrder: 2, sets: 2)
        addSuperset(in: antag, id: "a9", with: "a5", name: "Тяга гантели", bp: "back",  sortOrder: 3, sets: 3)

        // group: arms superset (a7<->a8)
        let arms = SDExerciseGroup(name: "Руки", sortOrder: 2)
        arms.template = template
        addSuperset(in: arms, id: "a7", with: "a8", name: "Бицепс",   bp: "arms", sortOrder: 0, sets: 3)
        addSuperset(in: arms, id: "a8", with: "a7", name: "Трицепс", bp: "arms", sortOrder: 1, sets: 3)

        return template
    }

    private static func buildTwoExerciseSupersetTemplate(
        in ctx: ModelContext
    ) -> SDTemplate {
        let plan = SDPlan(
            planType: "strength",
            planId: "test-rest-target",
            planName: "Test Rest Target",
            planVersion: 1,
            createdAt: .now
        )
        ctx.insert(plan)

        let template = SDTemplate(
            templateId: "day-rest-target",
            name: "Rest Target",
            sortOrder: 0
        )
        template.plan = plan

        let group = SDExerciseGroup(name: "Superset", sortOrder: 0)
        group.template = template
        addSuperset(
            in: group,
            id: "press",
            with: "row",
            name: "Press",
            bp: "chest",
            sortOrder: 0,
            sets: 2
        )
        addSuperset(
            in: group,
            id: "row",
            with: "press",
            name: "Row",
            bp: "back",
            sortOrder: 1,
            sets: 2
        )

        return template
    }

    private static func addStraight(
        in group: SDExerciseGroup,
        id: String, name: String, bp: String,
        sortOrder: Int, sets: Int
    ) {
        let ex = SDExercise(
            exerciseId: id, name: name, bodyPart: bp,
            restSeconds: 60, technique: "straight",
            sortOrder: sortOrder
        )
        ex.group = group
        for i in 0..<sets {
            let s = SDPrescribedSet(type: "working", reps: 12, weightKg: 10, rir: 1, sortOrder: i)
            s.exercise = ex
        }
    }

    private static func addSuperset(
        in group: SDExerciseGroup,
        id: String, with partnerId: String,
        name: String, bp: String,
        sortOrder: Int, sets: Int
    ) {
        let ex = SDExercise(
            exerciseId: id, name: name, bodyPart: bp,
            restSeconds: 60, technique: "superset",
            supersetWith: partnerId,
            sortOrder: sortOrder
        )
        ex.group = group
        for i in 0..<sets {
            let s = SDPrescribedSet(type: "working", reps: 12, weightKg: 10, rir: 1, sortOrder: i)
            s.exercise = ex
        }
    }
}
