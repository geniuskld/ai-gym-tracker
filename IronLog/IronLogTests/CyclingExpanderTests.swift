import XCTest
import SwiftData
@testable import IronLog

/// Pure-logic tests for `CyclingExpander.expand` -- the function that
/// flattens a template (with possible nested `interval_block` segments)
/// into the linear list of execution steps the workout runs through.
///
/// Helpers create a fresh `ModelContext(container)` (non-MainActor) so
/// the test methods can stay plain `throws` and be picked up by XCTest's
/// ObjC discovery.
final class CyclingExpanderTests: XCTestCase {

    // MARK: - Container helpers (nonisolated)

    private static func makeContext() throws -> ModelContext {
        let schema = Schema([
            SDCyclingPlan.self, SDCyclingTemplate.self,
            SDCyclingSegment.self, SDCyclingWorkout.self,
            SDCyclingSegmentLog.self,
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private static func makeTemplate(in ctx: ModelContext) -> SDCyclingTemplate {
        let plan = SDCyclingPlan(
            planId: "test", planName: "Test", planVersion: 1, createdAt: .now
        )
        ctx.insert(plan)
        let t = SDCyclingTemplate(templateId: "w1", name: "W1", sortOrder: 0)
        t.plan = plan
        return t
    }

    private static func addLeaf(
        to template: SDCyclingTemplate,
        kind: String, name: String, duration: Int,
        sortOrder: Int,
        targetMin: Int? = nil, targetMax: Int? = nil
    ) {
        let s = SDCyclingSegment(
            sortOrder: sortOrder, kind: kind, name: name,
            durationSeconds: duration,
            targetType: targetMin == nil ? "free" : "hr_bpm_range",
            targetMin: targetMin, targetMax: targetMax
        )
        s.template = template
    }

    private static func addBlock(
        to template: SDCyclingTemplate,
        name: String, repeats: Int, sortOrder: Int,
        children: [(kind: String, duration: Int, min: Int?, max: Int?)]
    ) {
        let block = SDCyclingSegment(
            sortOrder: sortOrder, kind: "interval_block",
            name: name, repeats: repeats
        )
        block.template = template
        for (i, c) in children.enumerated() {
            let child = SDCyclingSegment(
                sortOrder: i, kind: c.kind, name: c.kind,
                durationSeconds: c.duration,
                targetType: c.min == nil ? "free" : "hr_bpm_range",
                targetMin: c.min, targetMax: c.max
            )
            child.parent = block
        }
    }

    // MARK: - Tests

    /// A flat plan (no interval_block) expands 1:1 in template order.
    func testFlatTemplateExpandsOneToOne() throws {
        let ctx = try Self.makeContext()
        let t = Self.makeTemplate(in: ctx)
        Self.addLeaf(to: t, kind: "warmup",   name: "WU", duration: 600, sortOrder: 0)
        Self.addLeaf(to: t, kind: "steady",   name: "St", duration: 1200, sortOrder: 1)
        Self.addLeaf(to: t, kind: "cooldown", name: "CD", duration: 300, sortOrder: 2)

        let steps = CyclingExpander.expand(t)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.kind), ["warmup", "steady", "cooldown"])
        XCTAssertEqual(steps.map(\.durationSeconds), [600, 1200, 300])
    }

    /// `interval_block` with N repeats and M children expands to N*M leaves.
    func testIntervalBlockExpandsToProductOfRepeatsAndChildren() throws {
        let ctx = try Self.makeContext()
        let t = Self.makeTemplate(in: ctx)
        Self.addLeaf(to: t, kind: "warmup", name: "WU", duration: 600, sortOrder: 0)
        Self.addBlock(to: t, name: "4x4", repeats: 4, sortOrder: 1, children: [
            (kind: "work",     duration: 240, min: 150, max: 160),
            (kind: "recovery", duration: 180, min: 110, max: 120),
        ])
        Self.addLeaf(to: t, kind: "cooldown", name: "CD", duration: 300, sortOrder: 2)

        let steps = CyclingExpander.expand(t)
        XCTAssertEqual(steps.count, 10)
        XCTAssertEqual(steps.first?.kind, "warmup")
        XCTAssertEqual(steps.last?.kind, "cooldown")

        let body = steps.dropFirst().dropLast().map(\.kind)
        XCTAssertEqual(body, [
            "work", "recovery",
            "work", "recovery",
            "work", "recovery",
            "work", "recovery",
        ])

        let workSteps = steps.filter { $0.kind == "work" }
        XCTAssertEqual(workSteps.count, 4)
        for step in workSteps {
            XCTAssertEqual(step.targetMin, 150)
            XCTAssertEqual(step.targetMax, 160)
            XCTAssertTrue(step.hasHrTarget)
        }
    }

    /// Path strings are unique per execution step and stable across calls.
    func testStepPathsAreUniqueAndStable() throws {
        let ctx = try Self.makeContext()
        let t = Self.makeTemplate(in: ctx)
        Self.addBlock(to: t, name: "3x3", repeats: 3, sortOrder: 0, children: [
            (kind: "work",     duration: 180, min: 135, max: 145),
            (kind: "recovery", duration: 180, min: 110, max: 120),
        ])

        let stepsA = CyclingExpander.expand(t)
        let stepsB = CyclingExpander.expand(t)

        let pathsA = stepsA.map(\.path)
        let pathsB = stepsB.map(\.path)
        XCTAssertEqual(pathsA, pathsB, "expand should be deterministic")
        XCTAssertEqual(Set(pathsA).count, pathsA.count, "paths must be unique")

        XCTAssertTrue(pathsA.allSatisfy { $0.hasPrefix("block[0].rep[") })
    }

    /// totalDuration sums all expanded leaves (block contributes repeats * sum).
    func testTotalDurationSumsExpandedLeaves() throws {
        let ctx = try Self.makeContext()
        let t = Self.makeTemplate(in: ctx)
        Self.addLeaf(to: t, kind: "warmup",   name: "WU", duration: 600, sortOrder: 0)
        Self.addBlock(to: t, name: "3x3", repeats: 3, sortOrder: 1, children: [
            (kind: "work",     duration: 180, min: 135, max: 145),
            (kind: "recovery", duration: 180, min: 110, max: 120),
        ])
        Self.addLeaf(to: t, kind: "cooldown", name: "CD", duration: 300, sortOrder: 2)

        let total = CyclingExpander.totalDuration(for: t)
        XCTAssertEqual(total, 1980)
    }

    // MARK: - makeSchedule (wall-clock timeline)

    /// Without pause/skip offsets, each segment's `endsAt` is exactly
    /// `startedAt + cumulative_duration`. This is the foundation of the
    /// Live Activity self-advance: SwiftUI ticks `Text(timerInterval:)`
    /// past each `endsAt` and re-renders to pick the next segment.
    private static let workoutStart = Date(timeIntervalSince1970: 1_730_000_000)

    private static func sampleSteps() -> [CyclingExecStep] {
        [
            ("warmup",   600),
            ("work",     180),
            ("recovery", 180),
            ("cooldown", 300),
        ].enumerated().map { (i, t) in
            CyclingExecStep(
                path: "\(t.0)#\(i)",
                kind: t.0,
                name: t.0.capitalized,
                durationSeconds: t.1,
                targetType: nil,
                targetMin: nil,
                targetMax: nil,
                targetZoneLabel: nil,
                notes: nil
            )
        }
    }

    func testMakeScheduleProducesEndsAtPerStep() throws {
        let steps = Self.sampleSteps()
        let schedule = CyclingExpander.makeSchedule(
            steps: steps, startedAt: Self.workoutStart
        )
        XCTAssertEqual(schedule.count, 4)
        XCTAssertEqual(schedule[0].endsAt, Self.workoutStart.addingTimeInterval(600))
        XCTAssertEqual(schedule[1].endsAt, Self.workoutStart.addingTimeInterval(780))
        XCTAssertEqual(schedule[2].endsAt, Self.workoutStart.addingTimeInterval(960))
        XCTAssertEqual(schedule[3].endsAt, Self.workoutStart.addingTimeInterval(1260))

        // Step indices are 0-based and ascending
        XCTAssertEqual(schedule.map(\.stepIndex), [0, 1, 2, 3])
    }

    func testMakeScheduleShiftsAllEndsAtForwardOnPause() throws {
        let steps = Self.sampleSteps()
        let pause: TimeInterval = 90  // 90 s lost to pause
        let schedule = CyclingExpander.makeSchedule(
            steps: steps, startedAt: Self.workoutStart,
            pausedTotal: pause
        )
        // Every endsAt shifted forward by exactly the pause duration.
        XCTAssertEqual(schedule[0].endsAt, Self.workoutStart.addingTimeInterval(600 + pause))
        XCTAssertEqual(schedule[3].endsAt, Self.workoutStart.addingTimeInterval(1260 + pause))
    }

    func testMakeScheduleShiftsAllEndsAtBackwardOnSkipCredit() throws {
        let steps = Self.sampleSteps()
        let skip: TimeInterval = 120  // user skipped 2 min worth
        let schedule = CyclingExpander.makeSchedule(
            steps: steps, startedAt: Self.workoutStart,
            skipCredit: skip
        )
        XCTAssertEqual(schedule[0].endsAt, Self.workoutStart.addingTimeInterval(600 - skip))
        XCTAssertEqual(schedule[3].endsAt, Self.workoutStart.addingTimeInterval(1260 - skip))
    }

    func testMakeSchedulePauseAndSkipCombine() throws {
        let steps = Self.sampleSteps()
        let schedule = CyclingExpander.makeSchedule(
            steps: steps, startedAt: Self.workoutStart,
            pausedTotal: 60, skipCredit: 30
        )
        // Net offset: +60 - 30 = +30
        XCTAssertEqual(schedule[0].endsAt, Self.workoutStart.addingTimeInterval(600 + 30))
        XCTAssertEqual(schedule[3].endsAt, Self.workoutStart.addingTimeInterval(1260 + 30))
    }

    // MARK: - locate

    /// `locate` is the inverse of `makeSchedule`: given accumulated
    /// elapsed seconds, walks the steps and returns (currentStepIndex,
    /// secondsElapsedInThatStep). Used by the ViewModel's `tick()` to
    /// compute current state from wall-clock without an incremental
    /// counter (which dies in the background).

    func testLocateAtStartReturnsFirstStepZero() {
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 0, in: steps)
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(inStep, 0)
    }

    func testLocateInsideFirstStep() {
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 90, in: steps)
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(inStep, 90)
    }

    func testLocateAtStepBoundaryIsNextStep() {
        // At exactly 600 s -- step 0 (warmup, 600s) is just over.
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 600, in: steps)
        XCTAssertEqual(idx, 1, "boundary moment belongs to the next step")
        XCTAssertEqual(inStep, 0)
    }

    func testLocateInMiddleStep() {
        // 600 (warmup) + 90 into work = elapsed 690.
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 690, in: steps)
        XCTAssertEqual(idx, 1)
        XCTAssertEqual(inStep, 90)
    }

    func testLocatePastEndReturnsCountAndZero() {
        // Total = 1260 s. Elapsed = 5000 -> all done.
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 5000, in: steps)
        XCTAssertEqual(idx, steps.count)
        XCTAssertEqual(inStep, 0)
    }

    func testLocateMultipleStepsCrossedInOneJump() {
        // Simulates app being backgrounded for 15 minutes during a
        // 21-minute workout: elapsed = 900 s, expect to land in step 3
        // (cooldown), 120 s into it: 600 + 180 + 180 = 960 -- wait,
        // 900 < 960, so still in step 2 (recovery), 900 - 780 = 120 s in.
        let steps = Self.sampleSteps()
        let (idx, inStep) = CyclingExpander.locate(elapsed: 900, in: steps)
        XCTAssertEqual(idx, 2)
        XCTAssertEqual(inStep, 120)
    }
}
