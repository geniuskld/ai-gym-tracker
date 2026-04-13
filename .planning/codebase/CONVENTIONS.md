# Coding Conventions

**Analysis Date:** 2026-04-13

## Naming Patterns

**Files (Swift - iOS):**
- SwiftData models: `SD` prefix + PascalCase noun, e.g. `SDPlan.swift`, `SDWorkout.swift`, `SDExerciseLog.swift`
- JSON Codable structs: PascalCase + `JSON` suffix, e.g. `WorkoutPlanJSON.swift`, `WorkoutLogJSON.swift`
- Views: PascalCase describing the screen, e.g. `ActiveWorkoutView.swift`, `PlansListView.swift`
- ViewModels: PascalCase + `ViewModel` suffix, e.g. `ActiveWorkoutViewModel.swift`, `PlansViewModel.swift`
- Services: PascalCase + `Service`/`Manager`/`Helper` suffix, e.g. `PlanImportService.swift`, `SyncService.swift`, `HealthKitManager.swift`
- Technique flows: PascalCase + `Flow` suffix, e.g. `DropSetFlow.swift`, `SupersetFlow.swift`

**Files (Python - Server):**
- snake_case for all modules: `auth_routes.py`, `strength_v1.py`, `base.py`
- Route files named by resource: `plan.py`, `log.py`, `schema.py`

**Functions (Swift):**
- camelCase verbs: `startWorkout()`, `confirmPerforming()`, `skipExercise()`, `parseJSON()`
- Boolean computed properties use `is` prefix: `isSupported`, `isConfigured`, `isAuthenticated`, `isOvertime`
- Static factory/parse methods: `PlanImportService.parse()`, `PlanImportService.importPlan()`

**Functions (Python):**
- snake_case: `get_current_user()`, `validate_base()`, `hash_password()`
- Route handlers: descriptive verb + noun: `list_plans()`, `get_plan()`, `put_plan()`, `post_log()`
- Private helpers: underscore prefix: `_attach_refreshed_token()`, `_require_str()`, `_ensure_indexes()`

**Variables (Swift):**
- camelCase: `currentExerciseIndex`, `secondsRemaining`, `totalSeconds`
- Constants use `static let`: `PlanSchema.id`, `SyncService.defaultServerURL`

**Types (Swift):**
- Enums: PascalCase name, camelCase cases: `BodyPart.chest`, `Technique.dropSet`, `SetType.working`
- SwiftData models: `final class` with `@Model` macro
- ViewModels: `final class` with `@Observable` macro and `@MainActor`
- Protocols: PascalCase noun/adjective: `TechniqueFlow`

**Types (Python):**
- Pydantic models: PascalCase: `AuthRequest`, `AuthResponse`, `Settings`
- Enums: PascalCase: `PlanType`

## Code Style

**Formatting (Swift):**
- No external formatter (no SwiftFormat/SwiftLint config detected)
- 4-space indentation
- Trailing commas in multi-line arrays
- Opening braces on same line as declaration

**Formatting (Python):**
- No linter config detected (no ruff.toml, .flake8, pyproject.toml)
- 4-space indentation
- Double quotes for strings
- Type hints use Python 3.10+ union syntax: `str | None` (not `Optional[str]`)

## Import Organization

**Swift import order:**
1. `Foundation`
2. Apple frameworks (`SwiftUI`, `SwiftData`, `Combine`, `UIKit`, `UserNotifications`)
3. No third-party dependencies (pure Apple SDK)

**Python import order:**
1. Standard library (`json`, `time`, `uuid`, `datetime`)
2. Third-party (`fastapi`, `pydantic`, `bson`, `jose`, `passlib`, `motor`, `starlette`)
3. Local app imports (`app.auth`, `app.database`, `app.config`, `app.schemas`)

**Path Aliases:**
- None used in either platform. All imports are direct.

## Error Handling

**Swift Patterns:**
- Custom error enums conforming to `LocalizedError` with `errorDescription`:
  - `PlanImportError` in `PlanImportService.swift` (cases: `invalidJSON`, `emptyTemplates`, `duplicatePlan`)
  - `SyncError` in `SyncService.swift` (cases: `noServerURL`, `invalidURL`, `notAuthenticated`, `serverError`, `networkError`, `decodingError`)
- SwiftData saves use `try?` (fire-and-forget): `try? context.save()`
- Network calls in sync: `try await` with proper error propagation
- Fire-and-forget for non-critical operations (sync upload after workout save)

**Python Patterns:**
- Raise `HTTPException` with specific status codes and detail messages
- Validation errors use 422 status code consistently
- Auth errors use 401 status code
- Conflict errors use 409 (duplicate email, version conflict)

## Logging

**Swift:** No logging framework. Uses implicit `print` in debug builds only. `#if DEBUG` blocks for dev-only UI.

**Python:** Structured JSON logging via `AccessLogMiddleware` (prints JSON to stdout with timestamp, method, path, status, latency, request_id, IP).

## Comments

**When to Comment (Swift):**
- `// MARK: -` sections to organize files: `// MARK: - Properties`, `// MARK: - Set Flow`, `// MARK: - Helpers`
- `///` doc comments on protocol methods and key public APIs
- Brief inline comments for non-obvious logic: `// sync failed silently -- will remain unsynced`
- No JSDoc-style block comments

**When to Comment (Python):**
- Docstrings on validation functions: `"""Validate base plan fields present in the request body."""`
- Inline comments sparingly for step numbering: `# 1. Base field validation`, `# 2. Schema validation`

**Rule:** Never use non-ASCII characters in code comments (no arrows, em-dashes, etc.). Use only ASCII punctuation and standard Cyrillic letters.

## Function Design

**Size:** Most functions are under 40 lines. ViewModels are the largest files (~750 lines for `ActiveWorkoutViewModel.swift`).

**Parameters (Swift):**
- Named parameters with defaults: `importPlan(_ json:, into context:, replaceExisting: false)`
- Closures and trailing closure syntax for SwiftUI
- `@MainActor` on all ViewModels and UI-touching methods

**Parameters (Python):**
- FastAPI dependency injection via `Depends()`: `user: dict = Depends(get_current_user)`
- Request body parsed via `await request.json()` (raw dict, not Pydantic model) for plan routes
- Pydantic models for auth routes: `body: AuthRequest`

**Return Values (Swift):**
- Services return model objects: `importPlan() -> SDPlan`
- Parse methods return Codable structs: `parse() -> WorkoutPlanJSON`
- ViewModels expose state via `@Observable` properties (no return values)

## Module Design

**Exports (Swift):**
- No barrel files. Each file contains one primary type.
- Private helper views within the same file using `private struct` (e.g. `ReadyPhaseView`, `PerformingPhaseView` inside `ActiveWorkoutView.swift`)
- Extensions for helpers placed in the same file: `extension DecodingError` in `PlanImportService.swift`

**Exports (Python):**
- `__init__.py` used for re-exports: `app/schemas/__init__.py` exports `SCHEMA_REGISTRY` and `PlanType`
- Route modules export `router` variable consumed by `main.py`

## Two-Layer Model Pattern (Critical Convention)

**JSON Layer** (`IronLog/IronLog/Models/JSON/`):
- Pure `Codable` structs for parsing external JSON
- Use `snake_case` `CodingKeys` to match JSON wire format
- Enums with `String` raw values for type-safe parsing

**SwiftData Layer** (`IronLog/IronLog/Models/Data/`):
- `@Model` classes prefixed with `SD` to avoid naming conflicts
- Store enum values as raw `String` (not typed enums) for SwiftData compatibility
- Relationships use `@Relationship(deleteRule: .cascade, inverse:)` pattern
- `sortOrder: Int` on all ordered collections (templates, groups, exercises, sets)

**Conversion:** `PlanImportService.importPlan()` converts JSON layer to SwiftData layer.

## SwiftUI View Patterns

**State management:**
- `@State private var vm = ViewModel()` for view-owned ViewModels
- `@Bindable var vm: ViewModel` for passed-in ViewModels
- `@Query` for SwiftData queries directly in views
- `@Environment(\.modelContext)` for database access
- `@Environment(\.dismiss)` for navigation

**View structure:**
- Main view is a public `struct`
- Sub-views are `private struct` in the same file
- Sheets use `.sheet(isPresented:)` pattern
- Navigation uses `NavigationStack` with `.navigationDestination`
- `#if DEBUG` blocks for dev-only UI elements

## Server Architecture Patterns

**Route pattern:**
- Each route file creates `router = APIRouter(tags=["tag"])`
- JWT token refresh handled via `_attach_refreshed_token()` helper (duplicated in each route file)
- Auth via `Depends(get_current_user)` dependency injection
- MongoDB queries use `get_db()` accessor function
- Strip `_id` and `user_id` before returning documents to client

**Validation pattern:**
- Base validation in `app/schemas/base.py` (required fields check)
- Type-specific validation in schema modules (e.g. `strength_v1.validate()`)
- Schema registry maps plan_type string to validator module

---

*Convention analysis: 2026-04-13*
