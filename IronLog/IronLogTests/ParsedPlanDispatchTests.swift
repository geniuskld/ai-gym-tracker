import XCTest
import SwiftData
@testable import IronLog

/// `PlanImportService.parse` peeks `plan_type` and dispatches to either
/// the strength or cycling decoder, returning a `ParsedPlan` enum. These
/// tests pin that contract: known types decode to the correct variant,
/// unknown types throw, malformed input throws.
final class ParsedPlanDispatchTests: XCTestCase {

    func testParseStrengthDispatchesToStrengthVariant() throws {
        let json = """
        {
          "plan_type": "strength",
          "plan_id": "p1",
          "plan_version": 1,
          "plan_name": "Test",
          "schema": "2026-04-30T00:00:00Z",
          "created_at": "2026-04-27T00:00:00Z",
          "templates": [{
            "id": "d1", "name": "Day 1",
            "groups": [{
              "name": "Legs",
              "exercises": [{
                "id": "e1", "name": "Leg press",
                "catalog_id": "leg_press_machine",
                "body_part": "legs",
                "sets": [{"type": "working", "reps": 12}]
              }]
            }]
          }]
        }
        """
        let parsed = try PlanImportService.parse(json)
        guard case .strength(let plan) = parsed else {
            XCTFail("Expected .strength, got \(parsed)")
            return
        }
        XCTAssertEqual(plan.planId, "p1")
        XCTAssertEqual(plan.planVersion, 1)
        XCTAssertEqual(plan.templates.count, 1)
        XCTAssertEqual(
            plan.templates[0].groups[0].exercises[0].catalogId,
            "leg_press_machine"
        )
        XCTAssertEqual(parsed.planType, .strength)
    }

    @MainActor
    func testStrengthImportAndExportPreserveCatalogId() throws {
        let json = """
        {
          "plan_type": "strength",
          "plan_id": "p-catalog",
          "plan_version": 1,
          "plan_name": "Catalog Test",
          "schema": "2026-04-30T00:00:00Z",
          "created_at": "2026-04-30T00:00:00Z",
          "templates": [{
            "id": "d1", "name": "Day 1",
            "groups": [{
              "name": "Legs",
              "exercises": [{
                "id": "e1", "name": "Leg press",
                "catalog_id": "leg_press_machine",
                "body_part": "legs",
                "sets": [{"type": "working", "reps": 12, "weight_kg": 100}]
              }]
            }]
          }]
        }
        """
        let schema = Schema([
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
            SDCyclingPlan.self, SDCyclingTemplate.self, SDCyclingSegment.self,
            SDCyclingWorkout.self, SDCyclingSegmentLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        guard case .strength(let parsed) = try PlanImportService.parse(json) else {
            XCTFail("Expected strength plan")
            return
        }
        let plan = try PlanImportService.importStrength(parsed, into: context)
        let exercise = plan.templates[0].groups[0].exercises[0]
        XCTAssertEqual(exercise.catalogId, "leg_press_machine")

        let workout = SDWorkout(
            templateId: "d1",
            templateName: "Day 1",
            planType: "strength",
            planId: "p-catalog",
            planName: "Catalog Test",
            planVersion: 1
        )
        context.insert(workout)
        let exerciseLog = SDExerciseLog(
            exerciseId: exercise.exerciseId,
            catalogId: exercise.catalogId,
            exerciseName: exercise.name,
            bodyPart: exercise.bodyPart,
            order: 0
        )
        exerciseLog.workout = workout
        let setLog = SDSetLog(
            setNumber: 1,
            setType: "working",
            weightKg: 100,
            reps: 12
        )
        setLog.exerciseLog = exerciseLog
        try context.save()

        let exported = WorkoutExportService.workoutToJSON(workout)
        XCTAssertEqual(exported.exercises[0].catalogId, "leg_press_machine")
        XCTAssertEqual(exported.exercises[0].bodyPart, "legs")
    }

    func testParseCyclingDispatchesToCyclingVariant() throws {
        let json = """
        {
          "plan_type": "cycling",
          "plan_id": "c1",
          "plan_version": 1,
          "plan_name": "Test",
          "schema": "2026-04-27T00:00:00Z",
          "created_at": "2026-04-27T00:00:00Z",
          "templates": [{
            "id": "w1", "name": "W1",
            "segments": [
              {"kind": "warmup", "name": "WU", "duration_seconds": 600,
               "target": {"type": "hr_bpm_range", "min": 110, "max": 125}}
            ]
          }]
        }
        """
        let parsed = try PlanImportService.parse(json)
        guard case .cycling(let plan) = parsed else {
            XCTFail("Expected .cycling, got \(parsed)")
            return
        }
        XCTAssertEqual(plan.planId, "c1")
        XCTAssertEqual(plan.templates.first?.segments.count, 1)
        XCTAssertEqual(parsed.planType, .cycling)
    }

    func testParseUnknownPlanTypeThrows() {
        let json = """
        {"plan_type": "yoga", "plan_id": "y", "plan_version": 1,
         "plan_name": "x", "created_at": "2026-04-27T00:00:00Z", "templates": []}
        """
        XCTAssertThrowsError(try PlanImportService.parse(json)) { error in
            guard case PlanImportError.unknownPlanType(let t) = error else {
                XCTFail("Expected unknownPlanType, got \(error)")
                return
            }
            XCTAssertEqual(t, "yoga")
        }
    }

    func testParseInvalidJSONThrowsInvalidJSON() {
        XCTAssertThrowsError(try PlanImportService.parse("not json")) { error in
            guard case PlanImportError.invalidJSON = error else {
                XCTFail("Expected invalidJSON, got \(error)")
                return
            }
        }
    }

    func testParseEmptyTemplatesThrowsEmptyTemplates() {
        let json = """
        {"plan_type": "strength", "plan_id": "p", "plan_version": 1,
         "plan_name": "x", "schema": "2026-04-30T00:00:00Z",
         "created_at": "2026-04-27T00:00:00Z", "templates": []}
        """
        XCTAssertThrowsError(try PlanImportService.parse(json)) { error in
            guard case PlanImportError.emptyTemplates = error else {
                XCTFail("Expected emptyTemplates, got \(error)")
                return
            }
        }
    }

    // MARK: - Cycling import roundtrip

    @MainActor
    func testCyclingImportPersistsTemplatesAndSegments() throws {
        let json = """
        {
          "plan_type": "cycling",
          "plan_id": "norwegian-test",
          "plan_version": 1,
          "plan_name": "Test 4x4",
          "schema": "2026-04-27T00:00:00Z",
          "created_at": "2026-04-27T00:00:00Z",
          "templates": [{
            "id": "w1", "name": "Week 1",
            "segments": [
              {"kind": "warmup", "name": "WU", "duration_seconds": 600,
               "target": {"type": "hr_bpm_range", "min": 110, "max": 125}},
              {"kind": "interval_block", "name": "3x3", "repeats": 3, "children": [
                {"kind": "work", "name": "W", "duration_seconds": 180,
                 "target": {"type": "hr_bpm_range", "min": 135, "max": 145}},
                {"kind": "recovery", "name": "R", "duration_seconds": 180,
                 "target": {"type": "hr_bpm_range", "min": 110, "max": 120}}
              ]},
              {"kind": "cooldown", "name": "CD", "duration_seconds": 300,
               "target": {"type": "hr_bpm_range", "min": 90, "max": 110}}
            ]
          }]
        }
        """
        let schema = Schema([
            SDCyclingPlan.self, SDCyclingTemplate.self, SDCyclingSegment.self,
            SDCyclingWorkout.self, SDCyclingSegmentLog.self,
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let parsed = try PlanImportService.parse(json)
        try PlanImportService.importPlan(parsed, into: context)

        let plans = try context.fetch(FetchDescriptor<SDCyclingPlan>())
        XCTAssertEqual(plans.count, 1)
        let plan = plans[0]
        XCTAssertEqual(plan.planId, "norwegian-test")
        XCTAssertEqual(plan.planVersion, 1)
        XCTAssertEqual(plan.templates.count, 1)

        let template = plan.templates[0]
        XCTAssertEqual(template.segments.count, 3)

        // The block segment has its 2 children persisted as parent->children.
        let block = template.segments.first { $0.kind == "interval_block" }
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.repeats, 3)
        XCTAssertEqual(block?.children.count, 2)

        // CyclingExpander should expand template to 1 + 3*2 + 1 = 8 steps.
        XCTAssertEqual(CyclingExpander.expand(template).count, 8)
    }
}
