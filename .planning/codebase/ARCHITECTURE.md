# Architecture

**Analysis Date:** 2026-04-13

## Pattern Overview

**Overall:** Two-tier client-server system: iOS app (MVVM + Services) and Python sync server (FastAPI + MongoDB)

**Key Characteristics:**
- iOS app is the primary runtime; server is a sync/storage backend
- MVVM pattern on iOS with `@Observable` ViewModels and SwiftData persistence
- Two-layer model system: JSON Codable structs for parsing, `SD`-prefixed SwiftData `@Model` classes for persistence
- Strategy pattern for workout technique execution (TechniqueFlow protocol)
- Server uses schemaless MongoDB with manual validation (no Pydantic models for plan bodies)
- Plans are AI-generated JSON imported into the app; no manual plan creation in UI

## iOS App Layers

**Views (Presentation):**
- Purpose: SwiftUI views rendering UI and handling user interaction
- Location: `IronLog/IronLog/Views/`
- Contains: SwiftUI `View` structs organized by feature (Workout, Plans, History, Settings, Components)
- Depends on: ViewModels, Models/Data (via `@Query`)
- Used by: `ContentView` (tab-based root)

**ViewModels (State Management):**
- Purpose: Business logic, workout state machine, plan import orchestration
- Location: `IronLog/IronLog/ViewModels/`
- Contains: `@Observable` classes (`ActiveWorkoutViewModel`, `PlansViewModel`)
- Depends on: Models, Services, TechniqueFlows
- Used by: Views

**Models/JSON (Data Transfer):**
- Purpose: Mirror the JSON schema for encoding/decoding plans and workout logs
- Location: `IronLog/IronLog/Models/JSON/`
- Contains: `Codable` structs (`WorkoutPlanJSON`, `WorkoutLogJSON`, enums like `BodyPart`, `Technique`, `PlanType`)
- Depends on: Nothing
- Used by: Services (import, export, sync), ViewModels

**Models/Data (Persistence):**
- Purpose: SwiftData `@Model` classes for local storage
- Location: `IronLog/IronLog/Models/Data/`
- Contains: `SDPlan`, `SDTemplate`, `SDExerciseGroup`, `SDExercise`, `SDPrescribedSet`, `SDWorkout`, `SDExerciseLog`, `SDSetLog`
- Depends on: SwiftData framework
- Used by: Views (via `@Query`), ViewModels, Services

**Services (Infrastructure):**
- Purpose: Network communication, data import/export, timers, health integration
- Location: `IronLog/IronLog/Services/`
- Contains: `SyncService`, `PlanImportService`, `PlanSyncHelper`, `WorkoutExportService`, `RestTimerService`, `HealthKitManager`, `RestTimerActivity`, `SchemaRegistry`
- Depends on: Models, Foundation, HealthKit, ActivityKit
- Used by: ViewModels, Views

**TechniqueFlows (Workout Strategy):**
- Purpose: Strategy pattern implementations for each exercise technique
- Location: `IronLog/IronLog/TechniqueFlows/`
- Contains: `TechniqueFlow` protocol, `TechniqueFlowFactory`, concrete flows: `StraightFlow`, `DropSetFlow`, `RestPauseFlow`, `MyoRepsFlow`, `SupersetFlow`
- Depends on: `ExerciseState`, `SetState` (defined in `ActiveWorkoutViewModel`)
- Used by: `ActiveWorkoutViewModel`

**Widgets (Extension):**
- Purpose: Live Activity for rest timer on lock screen
- Location: `IronLog/IronLogWidgets/`
- Contains: `RestTimerLiveActivity` widget, shares `RestTimerActivity.swift` with main app
- Depends on: WidgetKit, ActivityKit

## Server Layers

**Application Entry:**
- Purpose: FastAPI app creation, middleware registration, router inclusion
- Location: `ironlog-server/app/main.py`
- Contains: Lifespan handler (DB connect/close), middleware stack, router registration

**Routes (API Endpoints):**
- Purpose: HTTP request handling, input validation, database operations
- Location: `ironlog-server/app/routes/`
- Contains: `auth_routes.py` (register/login), `plan.py` (CRUD plans), `log.py` (workout logs), `schema.py` (schema introspection)
- Depends on: `auth`, `database`, `schemas`

**Auth:**
- Purpose: JWT creation/verification, password hashing, user extraction from token
- Location: `ironlog-server/app/auth.py`
- Contains: `create_token`, `decode_token`, `get_current_user` (FastAPI dependency), `maybe_refresh_token`, bcrypt password helpers
- Uses: python-jose (JWT), passlib (bcrypt)

**Database:**
- Purpose: MongoDB connection management and index creation
- Location: `ironlog-server/app/database.py`
- Contains: Motor async client, `get_db()` accessor, index definitions for `users`, `plans`, `workout_logs`

**Schemas (Validation):**
- Purpose: Plan validation per plan_type, schema registry
- Location: `ironlog-server/app/schemas/`
- Contains: `__init__.py` (registry + `PlanType` enum), `base.py` (common field validation), `strength_v1.py` (strength plan validation)
- Pattern: Each plan type has its own validation module registered in `SCHEMA_REGISTRY`

**Middleware:**
- Purpose: Request ID tracking and structured access logging
- Location: `ironlog-server/app/middleware.py`
- Contains: `RequestIdMiddleware`, `AccessLogMiddleware`

**Config:**
- Purpose: Environment-based configuration via pydantic-settings
- Location: `ironlog-server/app/config.py`
- Contains: `Settings` class with MongoDB URL, JWT secret/expiry

## Data Flow

**Plan Import (JSON to SwiftData):**

1. User pastes JSON or picks file in `PlansListView` -> `PlansViewModel.parseJSON()`
2. `PlanImportService.parse()` decodes JSON into `WorkoutPlanJSON` Codable struct
3. User confirms in `PlanPreviewView` -> `PlansViewModel.confirmImport()`
4. `PlanImportService.importPlan()` creates `SDPlan` -> `SDTemplate` -> `SDExerciseGroup` -> `SDExercise` -> `SDPrescribedSet` hierarchy in SwiftData

**Plan Sync (Server to Client):**

1. `ContentView.task` calls `PlanSyncHelper.syncIfNeeded()` (throttled to 10 min)
2. `PlanSyncHelper.sync()` calls `SyncService.fetchPlan()` (GET /plan)
3. Compares `planVersion` with local; if server is newer, calls `PlanImportService.importPlan(replaceExisting: true)`
4. JWT auto-refresh: server returns `X-Refreshed-Token` header when token nears expiry

**Active Workout:**

1. User selects template in `TemplatePicker` -> `ActiveWorkoutViewModel.startWorkout()`
2. Creates `SDWorkout` in SwiftData, builds `ExerciseState`/`SetState` arrays from template
3. `TechniqueFlowFactory.makeFlow()` creates appropriate `TechniqueFlow` for current exercise
4. Flow-driven state machine: `ready` -> `performing` -> `resting` -> `ready` (next set/exercise)
5. Each completed set is incrementally persisted to SwiftData (`persistCompletedSet()`)
6. On finish: `saveWorkout()` writes final data, saves to HealthKit, uploads log to server (fire-and-forget)

**Workout Log Upload:**

1. `saveWorkout()` checks `SyncService.isConfigured && isAuthenticated && syncedAt == nil`
2. `WorkoutExportService.workoutToJSON()` converts `SDWorkout` -> `WorkoutJSON`
3. `SyncService.uploadWorkout()` sends POST /log
4. On success, marks `syncedAt` on the workout
5. On failure, silently ignores (workout stays unsynced)

**State Management:**
- iOS app uses `@Observable` (Observation framework) for ViewModels, not Combine
- SwiftData `@Query` in Views for reactive data fetching
- `RestTimerService` and `StopwatchService` use Combine `Timer.publish` internally for ticking
- Live Activities use ActivityKit for lock screen updates

## Key Abstractions

**TechniqueFlow Protocol:**
- Purpose: Encapsulates exercise progression logic per technique type
- Examples: `IronLog/IronLog/TechniqueFlows/StraightFlow.swift`, `DropSetFlow.swift`, `MyoRepsFlow.swift`, `SupersetFlow.swift`, `RestPauseFlow.swift`
- Pattern: Strategy pattern. Stateless flows that read `isCompleted` flags from `ExerciseState` array to determine next `TechniqueStep`. Factory creates the right flow via `TechniqueFlowFactory.makeFlow()`.
- Key types: `TechniqueStep` (instruction, suggested weight, rest, terminal flag), `TechniqueFlow` protocol

**Two-Layer Models:**
- Purpose: Separate JSON wire format from SwiftData persistence to avoid coupling
- JSON layer: `WorkoutPlanJSON`, `WorkoutLogJSON` in `Models/JSON/` -- pure `Codable` structs
- Data layer: `SDPlan`, `SDWorkout` etc. in `Models/Data/` -- `@Model` classes with relationships
- Bridge: `PlanImportService` (JSON -> SD), `WorkoutExportService` (SD -> JSON)

**Schema Validation:**
- Purpose: Ensure plan compatibility between AI-generated plans, server, and app
- Pattern: Each plan carries a `schema` timestamp. App validates structural compatibility via `SDPlan.isSupported`. Server validates via `strength_v1.validate()`. Schema JSON served at GET /schema.
- Key files: `IronLog/IronLog/Services/SchemaRegistry.swift` (client), `ironlog-server/app/schemas/strength_v1.py` (server)

## Entry Points

**iOS App:**
- Location: `IronLog/IronLog/IronLogApp.swift`
- Triggers: App launch
- Responsibilities: Creates SwiftData `ModelContainer` with all SD models, registers UserDefaults defaults, requests notification and HealthKit permissions

**ContentView (Tab Root):**
- Location: `IronLog/IronLog/ContentView.swift`
- Triggers: Loaded by `IronLogApp`
- Responsibilities: Four-tab navigation (Plans, Workout, History, Settings), auto-selects Workout tab if plans exist, triggers plan sync on appear

**Server App:**
- Location: `ironlog-server/app/main.py`
- Triggers: `uvicorn` via Docker
- Responsibilities: FastAPI app with lifespan (DB connect/disconnect), middleware (RequestId, AccessLog), four routers (auth, schema, plan, log)

## Error Handling

**Strategy:** Errors surface as user-facing messages in ViewModels; sync errors are silently ignored

**iOS Patterns:**
- `SyncError` enum with `LocalizedError` conformance in `IronLog/IronLog/Services/SyncService.swift`
- `PlanImportError` enum with `LocalizedError` conformance in `IronLog/IronLog/Services/PlanImportService.swift`
- `DecodingError` extension provides friendly error messages with JSON path
- ViewModels catch errors and set `.error(String)` state for UI display
- Sync failures (upload, auto-sync) are silently caught -- no user notification

**Server Patterns:**
- FastAPI `HTTPException` with status codes (401, 404, 409, 422)
- Validation errors return 422 with descriptive `detail` messages including field paths
- Middleware logs all requests with structured JSON (method, path, status, duration)

## Cross-Cutting Concerns

**Logging:** Server uses structured JSON access logs via `AccessLogMiddleware`. iOS has no logging framework; uses silent error swallowing for sync.

**Validation:** Server validates plans in two stages: base fields (`base.py`) then type-specific (`strength_v1.py`). Client validates structurally via `SDPlan.isSupported` (checks enums, non-empty collections).

**Authentication:** JWT Bearer tokens. Server creates tokens on register/login, validates via `get_current_user` dependency. Client stores JWT and email in iOS Keychain via `KeychainHelper`. Auto-refresh: server returns new token in `X-Refreshed-Token` header when current token is within 30 days of expiry.

---

*Architecture analysis: 2026-04-13*
