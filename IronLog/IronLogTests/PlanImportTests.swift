import XCTest
import SwiftData
@testable import IronLog

final class PlanImportTests: XCTestCase {

    // MARK: - Parse sample-plan.json

    func testParseSamplePlan() throws {
        let json = Self.samplePlanJSON
        let plan = try PlanImportService.parse(json)

        XCTAssertEqual(plan.version, "1.0")
        XCTAssertEqual(plan.planName, "Альбатрос Юг — Масса 2×/нед")
        XCTAssertEqual(plan.author, "Claude")
        XCTAssertEqual(plan.templates.count, 2)

        // Day A
        let dayA = plan.templates[0]
        XCTAssertEqual(dayA.id, "day-a")
        XCTAssertEqual(dayA.name, "День A")
        XCTAssertEqual(dayA.groups.count, 4)

        // Day A - legs
        let legs = dayA.groups[0]
        XCTAssertEqual(legs.name, "Ноги")
        XCTAssertEqual(legs.exercises.count, 3)

        // First exercise - leg press
        let legPress = legs.exercises[0]
        XCTAssertEqual(legPress.id, "a1")
        XCTAssertEqual(legPress.bodyPart, .legs)
        XCTAssertEqual(legPress.equipment, .machine)
        XCTAssertEqual(legPress.technique, .straight)
        XCTAssertEqual(legPress.restSeconds, 150)
        XCTAssertEqual(legPress.tempo, "2-2-1-0")
        XCTAssertEqual(legPress.stretchFocus, true)
        XCTAssertEqual(legPress.sets.count, 3)

        // Sets
        let set1 = legPress.sets[0]
        XCTAssertEqual(set1.type, .working)
        XCTAssertEqual(set1.repsMin, 10)
        XCTAssertEqual(set1.repsMax, 12)
        XCTAssertEqual(set1.rir, 2)

        // Drop set exercise
        let legExt = legs.exercises[1]
        XCTAssertEqual(legExt.technique, .dropSet)
        XCTAssertEqual(legExt.sets.count, 4)
        XCTAssertEqual(legExt.sets[1].type, .drop)
        XCTAssertEqual(legExt.sets[1].weightPercentDrop, 0.3)

        // Myo reps
        let legCurl = legs.exercises[2]
        XCTAssertEqual(legCurl.technique, .myoReps)

        // Day A - arms superset
        let arms = dayA.groups[3]
        XCTAssertEqual(arms.exercises.count, 2)
        XCTAssertEqual(arms.exercises[0].technique, .superset)
        XCTAssertEqual(arms.exercises[0].supersetWith, "a8")

        // Day B
        let dayB = plan.templates[1]
        XCTAssertEqual(dayB.id, "day-b")
        XCTAssertEqual(dayB.groups.count, 4)

        // Rest pause
        let legPressNarrow = dayB.groups[0].exercises[0]
        XCTAssertEqual(legPressNarrow.technique, .restPause)

        // Plate loaded
        let inclinePress = dayB.groups[1].exercises[0]
        XCTAssertEqual(inclinePress.equipment, .plateLoaded)
    }

    func testParseInvalidJSON() {
        XCTAssertThrowsError(try PlanImportService.parse("not json")) { error in
            XCTAssertTrue(error is PlanImportError)
        }
    }

    func testParseWrongVersion() {
        let json = """
        {"version":"2.0","plan_name":"Test","created_at":"2026-01-01T00:00:00Z","templates":[{"id":"t1","name":"T","groups":[]}]}
        """
        XCTAssertThrowsError(try PlanImportService.parse(json)) { error in
            guard case PlanImportError.unsupportedVersion = error else {
                XCTFail("Expected unsupportedVersion, got \(error)")
                return
            }
        }
    }

    func testParseEmptyTemplates() {
        let json = """
        {"version":"1.0","plan_name":"Test","created_at":"2026-01-01T00:00:00Z","templates":[]}
        """
        XCTAssertThrowsError(try PlanImportService.parse(json)) { error in
            guard case PlanImportError.emptyTemplates = error else {
                XCTFail("Expected emptyTemplates, got \(error)")
                return
            }
        }
    }

    @MainActor
    func testImportIntoSwiftData() throws {
        let json = try PlanImportService.parse(Self.samplePlanJSON)

        let schema = Schema([
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let plan = try PlanImportService.importPlan(json, into: context)

        XCTAssertEqual(plan.planName, "Альбатрос Юг — Масса 2×/нед")
        XCTAssertEqual(plan.templates.count, 2)

        let templates = plan.templates.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(templates[0].templateId, "day-a")
        XCTAssertEqual(templates[1].templateId, "day-b")

        let dayAGroups = templates[0].groups.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(dayAGroups.count, 4)
        XCTAssertEqual(dayAGroups[0].name, "Ноги")

        let exercises = dayAGroups[0].exercises.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(exercises.count, 3)
        XCTAssertEqual(exercises[0].exerciseId, "a1")
        XCTAssertEqual(exercises[0].technique, "straight")

        let sets = exercises[0].prescribedSets.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].type, "working")
        XCTAssertEqual(sets[0].repsMin, 10)
    }

    @MainActor
    func testDuplicateImportThrows() throws {
        let json = try PlanImportService.parse(Self.samplePlanJSON)

        let schema = Schema([
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        _ = try PlanImportService.importPlan(json, into: context)

        XCTAssertThrowsError(
            try PlanImportService.importPlan(json, into: context)
        ) { error in
            guard case PlanImportError.duplicatePlan = error else {
                XCTFail("Expected duplicatePlan, got \(error)")
                return
            }
        }
    }

    @MainActor
    func testReplaceExistingPlan() throws {
        let json = try PlanImportService.parse(Self.samplePlanJSON)

        let schema = Schema([
            SDPlan.self, SDTemplate.self, SDExerciseGroup.self,
            SDExercise.self, SDPrescribedSet.self,
            SDWorkout.self, SDExerciseLog.self, SDSetLog.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        _ = try PlanImportService.importPlan(json, into: context)
        let replaced = try PlanImportService.importPlan(
            json,
            into: context,
            replaceExisting: true
        )

        XCTAssertEqual(replaced.planName, "Альбатрос Юг — Масса 2×/нед")

        let allPlans = try context.fetch(FetchDescriptor<SDPlan>())
        XCTAssertEqual(allPlans.count, 1)
    }
}

// MARK: - Test data

extension PlanImportTests {
    static let samplePlanJSON = """
    {"version":"1.0","plan_name":"Альбатрос Юг — Масса 2×/нед","created_at":"2026-03-26T21:00:00Z","author":"Claude","notes":"Full body 2 раза в неделю.","templates":[{"id":"day-a","name":"День A","groups":[{"name":"Ноги","exercises":[{"id":"a1","name":"Жим ногами","body_part":"legs","equipment":"machine","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":2},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":150,"technique":"straight","tempo":"2-2-1-0","notes":"Пауза 2с в нижней точке.","stretch_focus":true},{"id":"a2","name":"Разгибание ног сидя","body_part":"legs","equipment":"machine","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3},{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3}],"rest_seconds":120,"technique":"drop_set"},{"id":"a3","name":"Сгибание ног лёжа","body_part":"legs","equipment":"machine","sets":[{"type":"working","reps_min":12,"reps_max":15,"rir":1}],"rest_seconds":90,"technique":"myo_reps"}]},{"name":"Грудь","exercises":[{"id":"a4","name":"Жим от груди Matrix","body_part":"chest","equipment":"machine","sets":[{"type":"working","reps_min":8,"reps_max":12,"rir":2},{"type":"working","reps_min":8,"reps_max":12,"rir":1},{"type":"working","reps_min":8,"reps_max":12,"rir":1}],"rest_seconds":150,"technique":"straight","tempo":"2-2-1-0","stretch_focus":true},{"id":"a5","name":"Fly на тренажёре","body_part":"chest","equipment":"machine","sets":[{"type":"working","reps_min":12,"reps_max":15,"rir":1},{"type":"working","reps_min":12,"reps_max":15,"rir":1}],"rest_seconds":90,"technique":"straight","stretch_focus":true}]},{"name":"Спина","exercises":[{"id":"a6","name":"Тяга верхнего блока","body_part":"back","equipment":"cable","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":2},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":120,"technique":"straight","stretch_focus":true}]},{"name":"Руки (суперсет)","exercises":[{"id":"a7","name":"Бицепс наклонная скамья","body_part":"arms","equipment":"dumbbell","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":90,"technique":"superset","superset_with":"a8","stretch_focus":true},{"id":"a8","name":"Трицепс над головой","body_part":"arms","equipment":"cable","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":90,"technique":"superset","superset_with":"a7","stretch_focus":true}]}]},{"id":"day-b","name":"День B","groups":[{"name":"Ноги","exercises":[{"id":"b1","name":"Жим ногами (узкая постановка)","body_part":"legs","equipment":"machine","sets":[{"type":"working","reps_min":8,"reps_max":12,"rir":0},{"type":"working","reps_min":8,"reps_max":12,"rir":0}],"rest_seconds":180,"technique":"rest_pause"},{"id":"b2","name":"Болгарские сплит-приседы","body_part":"legs","equipment":"dumbbell","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":2},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":90,"technique":"straight","stretch_focus":true},{"id":"b3","name":"Сгибание ног сидя","body_part":"legs","equipment":"machine","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3},{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3}],"rest_seconds":90,"technique":"drop_set","stretch_focus":true}]},{"name":"Грудь + плечи","exercises":[{"id":"b4","name":"Жим груди наклонный Olimp","body_part":"chest","equipment":"plate_loaded","sets":[{"type":"working","reps_min":8,"reps_max":12,"rir":2},{"type":"working","reps_min":8,"reps_max":12,"rir":1},{"type":"working","reps_min":8,"reps_max":12,"rir":1}],"rest_seconds":150,"technique":"straight","tempo":"2-2-1-0","stretch_focus":true},{"id":"b5","name":"Жим на плечи сидя","body_part":"shoulders","equipment":"machine","sets":[{"type":"working","reps_min":12,"reps_max":15,"rir":1}],"rest_seconds":120,"technique":"myo_reps"}]},{"name":"Спина","exercises":[{"id":"b6","name":"Тяга верхнего блока обратным хватом","body_part":"back","equipment":"cable","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"working","reps_min":10,"reps_max":12,"rir":0}],"rest_seconds":150,"technique":"rest_pause"},{"id":"b7","name":"Рычажная тяга Olimp","body_part":"back","equipment":"plate_loaded","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":2},{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":120,"technique":"straight","stretch_focus":true}]},{"name":"Руки (суперсет)","exercises":[{"id":"b8","name":"Молотки с гантелями","body_part":"arms","equipment":"dumbbell","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3},{"type":"working","reps_min":10,"reps_max":12,"rir":0},{"type":"drop","reps_min":6,"reps_max":8,"rir":0,"weight_percent_drop":0.3}],"rest_seconds":90,"technique":"superset","superset_with":"b9"},{"id":"b9","name":"Французский жим лёжа","body_part":"arms","equipment":"barbell","sets":[{"type":"working","reps_min":10,"reps_max":12,"rir":1},{"type":"working","reps_min":10,"reps_max":12,"rir":1}],"rest_seconds":90,"technique":"superset","superset_with":"b8","stretch_focus":true}]}]}]}
    """
}
