# Codebase Structure

**Analysis Date:** 2026-04-13

## Directory Layout

```
ai-gym-tracker/
├── IronLog/                        # iOS app (XcodeGen project)
│   ├── project.yml                 # XcodeGen project definition
│   ├── IronLog/                    # Main app target source
│   │   ├── IronLogApp.swift        # @main App entry point
│   │   ├── ContentView.swift       # Tab-based root view
│   │   ├── Info.plist              # App configuration
│   │   ├── IronLog.entitlements    # HealthKit entitlement
│   │   ├── Models/
│   │   │   ├── JSON/               # Codable structs (wire format)
│   │   │   └── Data/               # SwiftData @Model classes (persistence)
│   │   ├── ViewModels/             # @Observable view models
│   │   ├── Views/                  # SwiftUI views by feature
│   │   │   ├── Components/         # Reusable UI components
│   │   │   ├── History/            # Workout history
│   │   │   ├── Plans/              # Plan import and preview
│   │   │   ├── Settings/           # App settings
│   │   │   └── Workout/            # Active workout + template picker
│   │   ├── Services/               # Business logic, networking, timers
│   │   ├── TechniqueFlows/         # Strategy pattern for exercise techniques
│   │   ├── Utilities/              # (empty -- reserved)
│   │   └── Resources/              # Assets, sample data
│   ├── IronLogTests/               # Unit tests
│   ├── IronLogWidgets/             # Live Activity widget extension
│   └── IronLog.xcodeproj/          # Generated Xcode project (do not edit manually)
├── ironlog-server/                 # Python sync server
│   ├── Dockerfile                  # Python 3.12 container
│   ├── docker-compose.yml          # App + MongoDB orchestration
│   ├── requirements.txt            # Python dependencies
│   └── app/                        # FastAPI application
│       ├── __init__.py
│       ├── main.py                 # App factory, middleware, routers
│       ├── config.py               # pydantic-settings configuration
│       ├── database.py             # MongoDB connection + indexes
│       ├── auth.py                 # JWT + bcrypt auth logic
│       ├── middleware.py           # RequestId + AccessLog middleware
│       ├── routes/                 # API route handlers
│       │   ├── auth_routes.py      # POST /register, /login
│       │   ├── plan.py             # GET/PUT /plan, GET /plans, /plan/versions
│       │   ├── log.py              # POST/GET/DELETE /log
│       │   └── schema.py          # GET /schema
│       └── schemas/                # Plan validation modules
│           ├── __init__.py         # SCHEMA_REGISTRY + PlanType enum
│           ├── base.py             # Common base field validation
│           └── strength_v1.py      # Strength plan type validation
├── schemas/                        # JSON Schema documents (shared reference)
│   ├── workout-plan.schema.json    # Plan schema (served by server at GET /schema)
│   ├── workout-log.schema.json     # Log schema
│   └── sample-plan.json            # Example plan JSON
├── docs/                           # Documentation
│   ├── ARCHITECTURE.md             # Architecture overview
│   └── SPEC.md                     # Product specification
├── CLAUDE.md                       # AI assistant context
└── README.md                       # Project readme
```

## Directory Purposes

**`IronLog/IronLog/Models/JSON/`:**
- Purpose: Codable structs mirroring the JSON wire format
- Contains: `WorkoutPlanJSON.swift` (plan import schema), `WorkoutLogJSON.swift` (log export schema)
- Key types: `WorkoutPlanJSON`, `TemplateJSON`, `ExerciseJSON`, `PrescribedSetJSON`, `WorkoutLogJSON`, `WorkoutJSON`, `ExerciseLogJSON`, `SetLogJSON`
- Also contains domain enums: `PlanType`, `BodyPart`, `Equipment`, `SetType`, `Technique`, `LogSetType`, `TrainingGoal`

**`IronLog/IronLog/Models/Data/`:**
- Purpose: SwiftData persistence models (prefixed with `SD`)
- Contains: 8 `@Model` classes with cascade delete relationships
- Hierarchy: `SDPlan` -> `SDTemplate` -> `SDExerciseGroup` -> `SDExercise` -> `SDPrescribedSet` (plan structure), `SDWorkout` -> `SDExerciseLog` -> `SDSetLog` (workout logs)
- Key files: `SDPlan.swift`, `SDTemplate.swift`, `SDExerciseGroup.swift`, `SDExercise.swift`, `SDPrescribedSet.swift`, `SDWorkout.swift`, `SDExerciseLog.swift`, `SDSetLog.swift`

**`IronLog/IronLog/ViewModels/`:**
- Purpose: `@Observable` classes managing UI state and business logic
- Contains: `ActiveWorkoutViewModel.swift` (~750 lines, workout state machine), `PlansViewModel.swift` (~100 lines, plan import flow)
- State types `SetState`, `ExerciseState`, `SetPhase` are defined inside `ActiveWorkoutViewModel.swift`

**`IronLog/IronLog/Views/`:**
- Purpose: SwiftUI views organized by feature area
- `Components/`: `SlideButton.swift` (swipe-to-confirm gesture)
- `History/`: `WorkoutHistoryView.swift`
- `Plans/`: `PlansListView.swift`, `ImportView.swift`, `PlanPreviewView.swift`
- `Settings/`: `SettingsView.swift`
- `Workout/`: `TemplatePicker.swift` (template selection + workout resume), `ActiveWorkoutView.swift` (active workout UI), `DebugLogView.swift` (debug JSON export)

**`IronLog/IronLog/Services/`:**
- Purpose: Infrastructure services (networking, timers, data conversion)
- `SyncService.swift`: HTTP client for server API + Keychain helper (JWT, email storage)
- `PlanImportService.swift`: JSON parsing + SwiftData import logic
- `PlanSyncHelper.swift`: Auto-sync orchestration (throttled, compares versions)
- `WorkoutExportService.swift`: SDWorkout -> WorkoutLogJSON conversion
- `RestTimerService.swift`: Countdown timer + stopwatch (Combine Timer.publish)
- `RestTimerActivity.swift`: Live Activity attributes + manager (ActivityKit)
- `HealthKitManager.swift`: Singleton for saving workouts to Apple Health
- `SchemaRegistry.swift`: `PlanSchema.id` constant + `PlanType` enum

**`IronLog/IronLog/TechniqueFlows/`:**
- Purpose: Strategy implementations for exercise technique progression
- `TechniqueFlow.swift`: Protocol + `TechniqueStep` struct
- `TechniqueFlowFactory.swift`: Factory creating flows based on technique string
- `StraightFlow.swift`, `DropSetFlow.swift`, `RestPauseFlow.swift`, `MyoRepsFlow.swift`, `SupersetFlow.swift`: Concrete implementations

**`IronLog/IronLogWidgets/`:**
- Purpose: WidgetKit extension for Live Activity (rest timer on lock screen)
- Contains: `IronLogWidgetsBundle.swift` (widget entry point), `RestTimerLiveActivity.swift` (lock screen UI)
- Shares `RestTimerActivity.swift` from main app (compiled into both targets via `project.yml`)

**`IronLog/IronLogTests/`:**
- Purpose: Unit tests for plan import logic
- Contains: `PlanImportTests.swift`, `SamplePlanFileTests.swift`

**`ironlog-server/app/routes/`:**
- Purpose: FastAPI route handlers, one file per resource
- `auth_routes.py`: Registration and login
- `plan.py`: Plan CRUD with version management
- `log.py`: Workout log upsert, query, delete
- `schema.py`: Schema introspection endpoint

**`ironlog-server/app/schemas/`:**
- Purpose: Plan validation modules, one per plan_type
- `__init__.py`: `SCHEMA_REGISTRY` dict mapping plan_type string to validation module, dynamically creates `PlanType` enum
- `base.py`: Validates common fields (plan_type, plan_id, plan_version, plan_name, created_at)
- `strength_v1.py`: Validates strength plan structure (templates, groups, exercises, sets, enums)

**`schemas/`:**
- Purpose: Canonical JSON Schema documents shared between server and documentation
- `workout-plan.schema.json`: Plan format specification (served by server at GET /schema)
- `workout-log.schema.json`: Log format specification
- `sample-plan.json`: Example plan for testing

## Key File Locations

**Entry Points:**
- `IronLog/IronLog/IronLogApp.swift`: iOS app `@main` entry, SwiftData container setup
- `IronLog/IronLog/ContentView.swift`: Tab-based root view (Plans, Workout, History, Settings)
- `ironlog-server/app/main.py`: FastAPI app creation and configuration

**Configuration:**
- `IronLog/project.yml`: XcodeGen project definition (targets, settings, dependencies)
- `IronLog/IronLog/Info.plist`: iOS app configuration (ATS, HealthKit, Live Activities)
- `ironlog-server/app/config.py`: Server settings (MongoDB URL, JWT secret/expiry)
- `ironlog-server/docker-compose.yml`: Docker orchestration (app + MongoDB)

**Core Logic:**
- `IronLog/IronLog/ViewModels/ActiveWorkoutViewModel.swift`: Workout state machine (~750 lines)
- `IronLog/IronLog/Services/PlanImportService.swift`: JSON -> SwiftData plan import
- `IronLog/IronLog/Services/SyncService.swift`: All server communication + Keychain
- `IronLog/IronLog/TechniqueFlows/TechniqueFlow.swift`: Strategy protocol definition
- `ironlog-server/app/routes/plan.py`: Plan versioning and validation
- `ironlog-server/app/auth.py`: JWT lifecycle (create, decode, refresh)

**Testing:**
- `IronLog/IronLogTests/PlanImportTests.swift`: Plan import validation tests
- `IronLog/IronLogTests/SamplePlanFileTests.swift`: Sample plan file parsing tests

## Naming Conventions

**Files:**
- SwiftData models: `SD` prefix + entity name (e.g., `SDPlan.swift`, `SDWorkout.swift`)
- JSON models: entity name + `JSON` suffix (e.g., `WorkoutPlanJSON.swift`)
- Services: descriptive name + `Service`/`Manager`/`Helper` (e.g., `SyncService.swift`, `HealthKitManager.swift`)
- Views: feature name + `View` (e.g., `PlansListView.swift`, `ActiveWorkoutView.swift`)
- ViewModels: feature name + `ViewModel` (e.g., `ActiveWorkoutViewModel.swift`)
- TechniqueFlows: technique name + `Flow` (e.g., `DropSetFlow.swift`)
- Server routes: resource name (e.g., `plan.py`, `log.py`)
- Server schemas: plan_type + version (e.g., `strength_v1.py`)

**Directories:**
- iOS: PascalCase (e.g., `ViewModels/`, `TechniqueFlows/`)
- Server: lowercase (e.g., `routes/`, `schemas/`)

## Where to Add New Code

**New iOS Feature (e.g., new screen):**
- View: `IronLog/IronLog/Views/{FeatureName}/{FeatureName}View.swift`
- ViewModel (if needed): `IronLog/IronLog/ViewModels/{FeatureName}ViewModel.swift`
- Wire to tab or navigation in `IronLog/IronLog/ContentView.swift`

**New SwiftData Model:**
- Data model: `IronLog/IronLog/Models/Data/SD{EntityName}.swift`
- JSON model (if needed): `IronLog/IronLog/Models/JSON/{EntityName}JSON.swift`
- Register in `IronLogApp.swift` `Schema([...])` array

**New Exercise Technique:**
- Flow: `IronLog/IronLog/TechniqueFlows/{TechniqueName}Flow.swift`
- Register in `IronLog/IronLog/TechniqueFlows/TechniqueFlowFactory.swift` switch
- Add case to `Technique` enum in `IronLog/IronLog/Models/JSON/WorkoutPlanJSON.swift`
- Add to `VALID_TECHNIQUES` in `ironlog-server/app/schemas/strength_v1.py`

**New Plan Type (e.g., cardio):**
- Server validation module: `ironlog-server/app/schemas/{type}_v1.py` (must export `validate(data)` and `DESCRIPTION`)
- Register in `ironlog-server/app/schemas/__init__.py` `SCHEMA_REGISTRY`
- Add case to `PlanType` enum in `IronLog/IronLog/Services/SchemaRegistry.swift`
- Add JSON schema to `schemas/`

**New Server Endpoint:**
- Route handler: `ironlog-server/app/routes/{resource}.py`
- Register router in `ironlog-server/app/main.py`

**New iOS Service:**
- Service: `IronLog/IronLog/Services/{ServiceName}.swift`
- Pattern: Use `enum` namespace for stateless services, `final class` for stateful singletons

**Utilities:**
- iOS shared helpers: `IronLog/IronLog/Utilities/` (currently empty)

**Tests:**
- iOS unit tests: `IronLog/IronLogTests/{TestName}Tests.swift`

## Special Directories

**`IronLog/IronLog.xcodeproj/`:**
- Purpose: Generated Xcode project
- Generated: Yes, by XcodeGen from `project.yml`
- Committed: Yes, but should be regenerated via `cd IronLog && xcodegen generate`
- Do not edit manually

**`schemas/`:**
- Purpose: Canonical JSON Schema documents, shared reference for server and documentation
- Generated: No (hand-authored)
- Committed: Yes
- Server mounts this directory as Docker volume and serves it at GET /schema

**`IronLog/IronLog/Resources/`:**
- Purpose: Asset catalog (app icon, accent color) and sample data
- Contains: `Assets.xcassets/`, `sample-plan.json`
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-04-13*
