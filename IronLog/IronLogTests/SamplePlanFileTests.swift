import XCTest
@testable import IronLog

final class SamplePlanFileTests: XCTestCase {

    func testParseSamplePlanFile() throws {
        let url = URL(fileURLWithPath: "/Users/goryanin/Projects/ai-gym-tracker/schemas/sample-plan.json")
        let data = try Data(contentsOf: url)
        let plan = try PlanImportService.parse(data)

        XCTAssertEqual(plan.version, "1.0")
        XCTAssertEqual(plan.planName, "Альбатрос Юг — Масса 2\u{00d7}/нед")
        XCTAssertEqual(plan.templates.count, 2)

        // Day A: 4 groups, 8 exercises (3 legs + 2 chest + 1 back + 2 arms)
        let dayA = plan.templates[0]
        XCTAssertEqual(dayA.groups.count, 4)
        let dayAExerciseCount = dayA.groups.reduce(0) { $0 + $1.exercises.count }
        XCTAssertEqual(dayAExerciseCount, 8)

        // Day B: 4 groups, 9 exercises (3 legs + 2 chest/shoulders + 2 back + 2 arms)
        let dayB = plan.templates[1]
        XCTAssertEqual(dayB.groups.count, 4)
        let dayBExerciseCount = dayB.groups.reduce(0) { $0 + $1.exercises.count }
        XCTAssertEqual(dayBExerciseCount, 9)

        // All techniques present
        let allExercises = plan.templates.flatMap { $0.groups.flatMap(\.exercises) }
        let techniques = Set(allExercises.compactMap(\.technique))
        XCTAssertTrue(techniques.contains(.straight))
        XCTAssertTrue(techniques.contains(.dropSet))
        XCTAssertTrue(techniques.contains(.restPause))
        XCTAssertTrue(techniques.contains(.myoReps))
        XCTAssertTrue(techniques.contains(.superset))

        // All equipment types
        let equipments = Set(allExercises.compactMap(\.equipment))
        XCTAssertTrue(equipments.contains(.machine))
        XCTAssertTrue(equipments.contains(.cable))
        XCTAssertTrue(equipments.contains(.dumbbell))
        XCTAssertTrue(equipments.contains(.plateLoaded))
        XCTAssertTrue(equipments.contains(.barbell))
    }
}
