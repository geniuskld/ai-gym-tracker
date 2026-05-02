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
