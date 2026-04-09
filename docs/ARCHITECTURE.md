# IronLog -- Architecture Document

**Updated:** 2026-04-09
**Target:** iOS 17+, Swift, SwiftUI, SwiftData
**Pattern:** MVVM + Services
**Build:** XcodeGen (project.yml -> xcodeproj)
**Server:** Python, FastAPI, MongoDB, Docker

---

## 1. Project Structure

```
IronLog/
├── IronLogApp.swift                 # Entry point, SwiftData container, default settings
├── ContentView.swift                # Tab-based root: Plans / Active Workout / History / Settings
│
├── Models/
│   ├── JSON/                        # Codable structs for import/export
│   │   ├── WorkoutPlanJSON.swift    # Import schema types (PlanType enum)
│   │   └── WorkoutLogJSON.swift     # Export schema types (exerciseRating, planName, planType, planId)
│   │
│   └── Data/                        # SwiftData @Model classes (SD* prefix)
│       ├── SDPlan.swift             # Stored plan (planType, planId, planVersion)
│       ├── SDTemplate.swift         # Training day template
│       ├── SDExerciseGroup.swift    # Muscle group container
│       ├── SDExercise.swift         # Exercise definition (incl. maxMiniSets, notes)
│       ├── SDPrescribedSet.swift    # Prescribed set (type, reps, weightKg, rir, weightPercentDrop)
│       ├── SDWorkout.swift          # Workout session (planName, planType, planId)
│       ├── SDExerciseLog.swift      # Logged exercise (incl. exerciseRating)
│       └── SDSetLog.swift           # Logged individual set
│
├── Services/
│   ├── PlanImportService.swift      # JSON parsing, schema validation, SwiftData persistence
│   ├── WorkoutExportService.swift   # Build export JSON from SwiftData models
│   ├── RestTimerService.swift       # Countdown timer with haptics, notifications, Live Activity
│   ├── RestTimerActivity.swift      # ActivityKit: RestTimerAttributes + RestTimerActivityManager
│   ├── SyncService.swift            # Server sync: auth, plan fetch, log upload/delete, JWT/Keychain
│   └── SchemaRegistry.swift         # PlanType enum, PlanSchema.id (schema timestamp)
│
├── TechniqueFlows/                  # Stateless flow protocols for technique-specific set ordering
│   ├── TechniqueFlow.swift          # TechniqueFlow protocol + TechniqueStep struct
│   ├── TechniqueFlowFactory.swift   # Creates appropriate flow for exercise technique
│   ├── StraightFlow.swift           # Normal sequential sets
│   ├── DropSetFlow.swift            # Working set + drop sets (weight % reduction)
│   ├── MyoRepsFlow.swift            # Activation + mini-sets (with maxMiniSets limit)
│   ├── RestPauseFlow.swift          # Main set + short-rest continuations
│   └── SupersetFlow.swift           # Alternating between paired exercises
│
├── ViewModels/
│   ├── PlansViewModel.swift         # Plan list, import flow
│   └── ActiveWorkoutViewModel.swift # Core workout session: SetState, ExerciseState, phases
│
├── Views/
│   ├── Plans/
│   │   ├── PlansListView.swift      # List of plans + sync button
│   │   ├── ImportView.swift         # Paste JSON / pick file
│   │   └── PlanPreviewView.swift    # Preview before confirming import
│   │
│   ├── Workout/
│   │   ├── TemplatePicker.swift     # Choose template + resume banner + plan update banner
│   │   ├── ActiveWorkoutView.swift  # Main workout screen (all phases)
│   │   └── DebugLogView.swift       # Debug: view raw set data during workout
│   │
│   ├── History/
│   │   └── WorkoutHistoryView.swift # List + detail + swipe-delete (with server sync) + export
│   │
│   └── Settings/
│       └── SettingsView.swift       # Server URL, account (login/register/logout), test connection
│
├── Utilities/
│   └── Extensions.swift             # Date formatting, etc.
│
└── Resources/
    ├── Assets.xcassets/             # App icon (bicep+brain), AccentColor
    └── sample-plan.json             # Bundled example plan

IronLogWidgets/                      # Widget extension target (Live Activity UI)
├── Info.plist
├── IronLogWidgetsBundle.swift
└── RestTimerLiveActivity.swift      # Dynamic Island + Lock Screen Live Activity views

ironlog-server/                      # Sync server
├── app/
│   ├── main.py                      # FastAPI app, lifespan, middleware, routers
│   ├── config.py                    # pydantic-settings (JWT, MongoDB)
│   ├── auth.py                      # JWT (sliding 90d), bcrypt, maybe_refresh_token
│   ├── database.py                  # motor async client, get_db(), indexes
│   ├── middleware.py                # request_id, access log (JSON stdout)
│   ├── schemas/
│   │   ├── __init__.py              # SCHEMA_REGISTRY, PlanType enum
│   │   ├── base.py                  # Base contract validation (plan_name, created_at)
│   │   ├── strength_v1.py           # strength validation (groups, exercises, sets)
│   │   └── workout-plan.schema.json # JSON Schema for plan format (x-schema-id)
│   └── routes/
│       ├── auth_routes.py           # POST /register, POST /login
│       ├── plan.py                  # GET /plans, GET /plan, PUT /plan, GET /plan/versions
│       ├── log.py                   # POST /log, GET /log, DELETE /log/{id}
│       └── schema.py               # GET /schema (public)
├── Dockerfile
├── docker-compose.yml
└── requirements.txt
```

---

## 2. Data Flow

```
Claude (AI)
    |
    v
Sync Server (FastAPI + MongoDB)
    |                        ^
    | GET /plan              | POST /log
    v                        |
iOS App (SwiftData)  ------->
    |
    v
PlanImportService --> SDPlan -> SDTemplate -> SDExercise -> SDPrescribedSet
    |
    v
ActiveWorkoutViewModel
    |-- builds ExerciseState[] + SetState[] from SDTemplate
    |-- creates TechniqueFlow via TechniqueFlowFactory
    |-- manages SetPhase: ready -> performing -> resting -> ratingExercise
    |-- updates Live Activity (performing / resting / overtime)
    |
    v
SDWorkout + SDExerciseLog + SDSetLog
    |
    v
SyncService.uploadWorkout() --> POST /log (fire-and-forget)
WorkoutExportService --> JSON (Share Sheet / clipboard)
```

---

## 3. Sync Architecture

### Auth
- Email/password -> JWT (90-day sliding expiry)
- При каждом запросе: если до expiry < 30 дней -> X-Refreshed-Token header
- Клиент хранит JWT + email в Keychain
- 401 -> token очищается, пользователь переходит на логин

### Plan Sync
- При запуске TemplatePicker: GET /plan -> сравнить plan_version
- Если новая версия + schema поддерживается -> баннер "Update"
- Если schema не поддерживается -> баннер "Update app"
- PlansListView: ручная кнопка "Sync Plan"

### Log Sync
- После завершения тренировки: SyncService.uploadWorkout() (fire-and-forget)
- При swipe-to-delete: SyncService.deleteWorkout() (fire-and-forget)
- Upsert по workout ID на сервере

### Schema & Compatibility
- Каждый план несет поле `schema` -- timestamp идентификатор схемы (e.g. `"2026-04-09T22:00:00Z"`)
- Серверная JSON-схема содержит `x-schema-id` с тем же timestamp; Claude копирует его в план
- Приложение хранит `PlanSchema.id` -- timestamp своей поддерживаемой схемы
- **Валидация структурная**: приложение проверяет plan_type, body_part, technique, наличие templates/groups/exercises/sets
- Загруженные планы не проходящие валидацию -> "not supported" + timestamps обеих схем
- Ответ сервера не декодируется -> баннер "Update app"
- PlanType -- enum на обеих сторонах (Python Enum, Swift enum), сейчас: `strength`
- Неизвестный plan_type -> 422

---

## 4. SwiftData Models -- Design Decisions

### Two-layer model strategy
- **Layer 1: JSON Codable structs** -- pure value types, 1:1 mirror of JSON schemas, no SwiftData deps
- **Layer 2: SwiftData @Model classes** -- prefixed with `SD`, relationships via SwiftData, source of truth

### Shared Base Contract
Каждый план содержит обязательные поля:
- `plan_type` -- тип плана (strength, в будущем cycling, cardio, ...)
- `plan_id` -- стабильный slug (не меняется при переименовании)
- `plan_version` -- инкрементальная версия содержимого
- `plan_name` -- человекочитаемое название
- `schema` -- timestamp идентификатор схемы (для отладки совместимости)
- `created_at` -- дата создания

### Weight prefill strategy
- Каждый PrescribedSet может иметь optional `weight_kg` (из плана)
- Первая тренировка: вес из плана
- Последующие: вес из прошлой тренировки того же упражнения/сета
- Fallback: previous workout -> plan -> empty (ручной ввод)

### Key relationships
```
SDPlan (1) --> (N) SDTemplate
SDTemplate (1) --> (N) SDExerciseGroup
SDExerciseGroup (1) --> (N) SDExercise
SDExercise (1) --> (N) SDPrescribedSet

SDWorkout (1) --> (N) SDExerciseLog
SDExerciseLog (1) --> (N) SDSetLog
SDWorkout.templateId -> string FK to SDTemplate (survives re-import)
SDExerciseLog.exerciseId -> string FK to SDExercise (survives re-import)
```

---

## 5. Active Workout -- State Machine

### Workout States
```
IDLE -> ACTIVE -> LOGGING_SET <-> REST_TIMER -> ... -> FINISHING -> SAVED
                      |
                      v
                RATING_EXERCISE (optional, between exercises)
```

### Set Phases (within a set)
```
ready -> performing -> resting -> ready (next set)
```

- **ready**: shows SetRoadmap, slide right = start, slide left = set weight
- **performing**: stopwatch running, Live Activity shows weight + timer
- **resting**: countdown timer, Live Activity shows countdown, overtime pulsing
- **ratingExercise**: Heavy/OK/Easy rating between exercises (optional)

### TechniqueFlow Protocol

Stateless protocol -- each call to `nextStep()` returns the next action based on current state:

```swift
protocol TechniqueFlow {
    var exerciseIndices: [Int] { get }
    var displayName: String? { get }
    func nextStep(
        exercises: [ExerciseState],
        completedExerciseIndex: Int?,
        completedSetIndex: Int?,
        completedReps: Int?
    ) -> TechniqueStep?
}
```

| Technique | Behavior | Timer |
|-----------|----------|-------|
| `straight` | Sequential sets with rest | After each set |
| `drop_set` | Working + drop (reduce weight %) | After last drop only |
| `rest_pause` | Main set + short-rest continuations | 15-20s between continuations |
| `myo_reps` | Activation + mini-sets (limited) | 5s between minis |
| `superset` | Alternate between paired exercises | After both exercises |

---

## 6. Dynamic Island + Live Activity

### Architecture
- **RestTimerAttributes** (ActivityAttributes): shared between app and widget via source file inclusion
- **RestTimerActivityManager**: singleton, manages activity lifecycle (start/update/end)
- **RestTimerLiveActivity**: Widget with Dynamic Island (compact/expanded/minimal) + Lock Screen

### Phases
| Phase | Compact Leading | Compact Trailing | Expanded |
|-------|----------------|-----------------|----------|
| Performing | dumbbell + weight | weight (green) | exercise name + weight + "Working set" |
| Resting | timer icon | countdown (blue) | exercise + next label + progress bar |
| Overtime | timer icon | "GO!" (yellow) | exercise + next label + yellow progress |

---

## 7. UI Components (ActiveWorkoutView)

| Component | Purpose |
|-----------|---------|
| ExerciseHeader | Exercise name, technique badge, superset indicator, notes |
| SetRoadmap | Visual list of all sets: active (bold), pending (gray), completed (faded) |
| WeightStepper | -5/-1/+1/+5 kg step buttons with large weight display |
| SlideButton | Dual-action swipe button (left/right) for set flow |
| ExerciseListSheet | Full exercise list as sheet with progress, body part, technique badge |
| ExerciseRatingView | Heavy/OK/Easy rating between exercises |
| RestingPhaseView | Circular timer with progress ring, next set label, "Finish exercise" button |

---

## 8. Sprint History

### Sprint 1: Foundation
- Xcode project (XcodeGen), JSON Codable models, SwiftData models
- PlanImportService, Plans UI (list, import, preview)
- Basic ActiveWorkout: template picker, set logging, rest timer

### Sprint 2: UX + Features
- TechniqueFlow system (straight, drop, myo, rest-pause, superset)
- Dynamic Island + Lock Screen Live Activity
- App icon (golden bicep with blue brain)
- SetRoadmap, WeightStepper, Exercise list sheet
- Exercise rating (Heavy/OK/Easy) + export
- Workout history: swipe-delete, ShareLink export, planName
- max_mini_sets for myo-reps, warmup sets
- Schema documentation

### Sprint 3: Sync Server + Auth
- Sync-сервер: FastAPI + MongoDB + Docker
- JWT auth (sliding 90-day expiry, bcrypt)
- Shared Base Contract (plan_type, plan_id, plan_version, schema)
- PlanType enum (server + client синхронизированы)
- Schema identification (timestamp в плане + структурная валидация в приложении)
- Plan sync: auto-check + manual + update banner
- Log sync: fire-and-forget upload + delete
- Keychain storage (JWT, email)
- Settings: server URL, account management
- ATS exception для HTTP
- Exercise notes из плана
