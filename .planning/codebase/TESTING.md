# Testing Patterns

**Analysis Date:** 2026-04-13

## Test Framework

**Runner (iOS):**
- XCTest (Apple built-in)
- Config: `IronLog/project.yml` defines `IronLogTests` target
- Test host: `IronLog.app` (hosted unit tests)

**Assertion Library:**
- XCTest built-in assertions: `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertThrowsError`

**Runner (Server):**
- No test framework detected. No test files exist in `ironlog-server/`.
- No pytest, unittest, or any test configuration.

**Run Commands:**
```bash
# iOS tests (via Xcode)
xcodebuild test -scheme IronLog -destination 'platform=iOS Simulator,name=iPhone 15'

# Server tests
# None configured
```

## Test File Organization

**Location:**
- iOS: Separate test target directory `IronLog/IronLogTests/`
- Server: No tests exist

**Naming:**
- `*Tests.swift` suffix: `PlanImportTests.swift`, `SamplePlanFileTests.swift`

**Structure:**
```
IronLog/
  IronLogTests/
    PlanImportTests.swift      # Plan parsing + SwiftData import tests
    SamplePlanFileTests.swift  # Validates sample-plan.json file from schemas/
```

## Test Structure

**Suite Organization:**
```swift
import XCTest
import SwiftData
@testable import IronLog

final class PlanImportTests: XCTestCase {

    // MARK: - Parse sample-plan.json

    func testParseSamplePlan() throws {
        let json = Self.samplePlanJSON
        let plan = try PlanImportService.parse(json)
        XCTAssertEqual(plan.version, "1.0")
        // ... detailed field assertions
    }

    func testParseInvalidJSON() {
        XCTAssertThrowsError(try PlanImportService.parse("not json")) { error in
            XCTAssertTrue(error is PlanImportError)
        }
    }
}

// MARK: - Test data

extension PlanImportTests {
    static let samplePlanJSON = """
    { ... inline JSON ... }
    """
}
```

**Patterns:**
- Setup: In-memory SwiftData container created per test method (no shared setup)
- Teardown: None needed (in-memory containers auto-cleanup)
- Assertions: Detailed field-by-field verification, not snapshot testing
- Test data: Inline JSON strings as `static let` in extensions

## In-Memory SwiftData Container Pattern

Each test that needs persistence creates its own container:

```swift
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
    XCTAssertEqual(plan.planName, "...")
}
```

**Key details:**
- All 8 SwiftData model types must be included in the schema
- `isStoredInMemoryOnly: true` for test isolation
- Tests requiring SwiftData use `@MainActor` annotation
- `container.mainContext` provides the test context

## Mocking

**Framework:** None

**Patterns:** No mocking is used. Tests call real service methods with in-memory data stores.

**What to Mock (if adding tests):**
- `SyncService` network calls (currently uses real URLSession)
- `HealthKitManager` (currently no tests touch HealthKit)
- `KeychainHelper` (currently untested)

**What NOT to Mock:**
- `PlanImportService` parsing logic (test directly)
- SwiftData operations (use in-memory containers)

## Fixtures and Factories

**Test Data:**
```swift
// Inline JSON as static properties on test classes
extension PlanImportTests {
    static let samplePlanJSON = """
    {"version":"1.0","plan_name":"...","templates":[...]}
    """
}
```

**Location:**
- Test data is embedded directly in test files as static properties
- `SamplePlanFileTests` reads from the actual schema file at an absolute path: `/Users/goryanin/Projects/ai-gym-tracker/schemas/sample-plan.json`

**No factory/builder pattern exists.** Each test constructs data inline.

## Coverage

**Requirements:** None enforced. No coverage configuration.

**View Coverage:**
```bash
# Not configured
```

## Test Types

**Unit Tests (iOS):**
- `PlanImportTests`: 6 tests covering JSON parsing, validation, SwiftData import, duplicate detection, and replacement
  - `testParseSamplePlan()` - Happy path with full field verification
  - `testParseInvalidJSON()` - Invalid input error handling
  - `testParseWrongVersion()` - Removed; schema version validation
  - `testParseEmptyTemplates()` - Empty templates validation
  - `testImportIntoSwiftData()` - Full import pipeline
  - `testDuplicateImportThrows()` - Duplicate detection
  - `testReplaceExistingPlan()` - Replace existing plan

- `SamplePlanFileTests`: 1 test validating the sample plan file
  - `testParseSamplePlanFile()` - Reads and parses the actual sample-plan.json from the schemas/ directory; verifies all techniques and equipment types are present

**Integration Tests:** None

**E2E Tests:** None

**Server Tests:** None exist. The Python server has no test files, no pytest config, no test fixtures.

## Common Patterns

**Error Testing:**
```swift
func testParseInvalidJSON() {
    XCTAssertThrowsError(try PlanImportService.parse("not json")) { error in
        XCTAssertTrue(error is PlanImportError)
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
```

**Pattern for error case matching:** Use `guard case` inside `XCTAssertThrowsError` closure, with `XCTFail` for unexpected error types.

## Untested Areas

**iOS - No test coverage for:**
- `ActiveWorkoutViewModel` (largest, most complex file: ~750 lines)
- `SyncService` network operations
- `RestTimerService` / `StopwatchService` timing logic
- `WorkoutExportService` JSON export
- All TechniqueFlow implementations (`DropSetFlow`, `SupersetFlow`, `RestPauseFlow`, `MyoRepsFlow`)
- `TechniqueFlowFactory` routing logic
- `PlansViewModel` state machine
- `HealthKitManager` integration
- `PlanSyncHelper` server sync logic
- All SwiftUI Views (no UI/snapshot tests)
- `SchemaRegistry` / `PlanSchema` validation logic

**Server - Complete absence of tests:**
- No route tests
- No auth tests
- No validation tests
- No database integration tests

## Adding New Tests

**For iOS unit tests:**
1. Create file in `IronLog/IronLogTests/` with `*Tests.swift` naming
2. Import `XCTest`, `SwiftData`, and `@testable import IronLog`
3. Subclass `XCTestCase`
4. For SwiftData tests: create in-memory container with all 8 model types
5. Mark SwiftData test methods with `@MainActor`

**For server tests (if adding):**
1. Add `pytest` and `httpx` to `requirements.txt`
2. Create `ironlog-server/tests/` directory
3. Use FastAPI's `TestClient` for route testing
4. Mock MongoDB with `mongomock` or use a test database

---

*Testing analysis: 2026-04-13*
