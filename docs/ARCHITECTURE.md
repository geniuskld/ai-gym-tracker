# IronLog -- Architecture Document

**Updated:** 2026-04-30
**Target:** iOS 17+, watchOS 10+, Swift, SwiftUI, SwiftData
**Pattern:** MVVM + Services
**Build:** XcodeGen (project.yml -> xcodeproj)
**Server:** Python, FastAPI, MongoDB, Docker

---

## 1. Project Structure

```
IronLog/                                  # iOS app
├── IronLogApp.swift                      # Entry point, SwiftData container, default settings,
│                                           CrashReporter.install + uploadPending
├── ContentView.swift                     # Tab-based root: Plans / Active Workout / History / Settings
│
├── Models/
│   ├── JSON/                             # Codable structs for import/export
│   │   ├── WorkoutPlanJSON.swift         # Strength import schema (PlanType, BodyPart, ...)
│   │   ├── WorkoutLogJSON.swift          # Strength export schema
│   │   ├── CyclingPlanJSON.swift         # Cycling import schema (segments, interval_block, target)
│   │   └── CyclingWorkoutLogJSON.swift   # Cycling export schema (per-segment HR/duration)
│   │
│   └── Data/                             # SwiftData @Model classes (SD* prefix)
│       ├── SDPlan.swift                  # Strength plan
│       ├── SDTemplate.swift              # Strength workout template
│       ├── SDExerciseGroup.swift         # Muscle group container
│       ├── SDExercise.swift              # Exercise definition
│       ├── SDPrescribedSet.swift         # Prescribed set
│       ├── SDWorkout.swift               # Strength workout session
│       ├── SDExerciseLog.swift           # Logged exercise
│       ├── SDSetLog.swift                # Logged set
│       ├── SDCyclingPlan.swift           # Cycling plan
│       ├── SDCyclingTemplate.swift       # Cycling workout (one session)
│       ├── SDCyclingSegment.swift        # Self-referential: leaf or interval_block w/ children
│       ├── SDCyclingWorkout.swift        # Cycling workout session
│       └── SDCyclingSegmentLog.swift     # Per-segment log (duration, HR, in-zone seconds)
│
├── Services/
│   ├── PlanImportService.swift           # ParsedPlan enum + plan_type peek + per-type import
│   ├── WorkoutExportService.swift        # Strength + cycling export to JSON
│   ├── RestTimerService.swift            # Countdown timer (haptics, notifications, Live Activity)
│   ├── RestTimerActivity.swift           # ActivityKit attributes + manager
│   ├── SyncService.swift                 # JWT/Keychain, /plans, /log, /crash, /log (cycling)
│   ├── PlanSyncHelper.swift              # Pull-then-import per-plan-type dispatcher
│   ├── SchemaRegistry.swift              # PlanType enum + per-type schema timestamp ids
│   ├── CrashReporter.swift               # NSException + signal handlers, write JSON to disk,
│   │                                       upload pending on launch
│   ├── HRSource.swift                    # Protocol + NoHRSource + HRSourceResolver
│   ├── WatchHRSource.swift               # Live HR via WatchConnectivity (Phase 2)
│   ├── WorkoutSessionManager.swift       # WCSession central delegate: start/stop watch session,
│   │                                       receive hr_sample events
│   └── HealthKitManager.swift            # HealthKit auth + workout writes
│
├── TechniqueFlows/                       # Stateless flows for strength technique-specific ordering
│   ├── TechniqueFlow.swift               # Protocol + TechniqueStep
│   ├── TechniqueFlowFactory.swift        # Picks flow by exercise.technique
│   ├── StraightFlow.swift                # Sequential
│   ├── DropSetFlow.swift                 # Working + drop
│   ├── MyoRepsFlow.swift                 # Activation + dynamic mini-sets
│   ├── RestPauseFlow.swift               # Main + short-rest continuations
│   └── SupersetFlow.swift                # Alternating between paired exercises
│                                          (multiple independent pairs in one group supported)
│
├── ViewModels/
│   ├── PlansViewModel.swift              # State machine for parse/preview/import (ParsedPlan)
│   ├── ActiveWorkoutViewModel.swift      # Strength workout state machine
│   └── CyclingWorkoutViewModel.swift     # Cycling executor: expand template, tick, per-step metrics
│
├── Views/
│   ├── Plans/
│   │   ├── PlansListView.swift           # Two sections: Strength + Cycling, sync, import
│   │   ├── ImportView.swift              # Paste / pick file
│   │   └── PlanPreviewView.swift         # Per-type preview before confirming import
│   │
│   ├── Workout/
│   │   ├── TemplatePicker.swift          # AnyPlanHandle -> route to strength or cycling executor
│   │   ├── ActiveWorkoutView.swift       # Strength executor
│   │   ├── CyclingWorkoutView.swift      # Cycling executor: timer, target HR, controls
│   │   └── DebugLogView.swift            # Debug raw set data
│   │
│   ├── History/
│   │   └── WorkoutHistoryView.swift      # Strength workout history (cycling history TBD)
│   │
│   └── Settings/
│       └── SettingsView.swift            # Server URL, account, test connection
│
├── Utilities/
└── Resources/
    ├── Assets.xcassets/
    └── sample-plan.json

IronLogWidgets/                           # Widget extension target (Live Activity UI for strength)
├── IronLogWidgetsBundle.swift
└── RestTimerLiveActivity.swift

IronLogWatch/                             # watchOS app target
├── IronLogWatchApp.swift                 # Entry, requests HealthKit auth
├── WatchWorkoutManager.swift             # HKWorkoutSession (cycling | strength), HR forwarding
└── LiveWorkoutView.swift                 # Active workout display: HR, timer, calories

IronLogTests/                             # XCTest target
├── MultipleSupersetPairsTests.swift      # ActiveWorkoutVM integration: v12 multi-superset layout
├── CyclingExpanderTests.swift            # interval_block expansion, paths, totalDuration
├── ParsedPlanDispatchTests.swift         # parse strength/cycling/unknown + import roundtrip
└── CrashReporterTests.swift              # idempotent install, safe uploadPending no-op

ironlog-server/                           # Sync server
├── app/
│   ├── main.py                           # FastAPI app, lifespan, middleware, routers
│   ├── config.py                         # pydantic-settings (JWT, MongoDB)
│   ├── auth.py                           # JWT (sliding 90d), bcrypt
│   ├── database.py                       # motor async client, get_db()
│   ├── middleware.py                     # request_id, access log
│   ├── schemas/
│   │   ├── __init__.py                   # SCHEMA_REGISTRY {strength, cycling} + PlanType enum
│   │   ├── base.py                       # Base contract validation (plan_type, plan_id, ...)
│   │   ├── strength_v1.py                # Strength validator (groups -> exercises -> sets)
│   │   └── cycling_v1.py                 # Cycling validator (segments, target, repeats, max-depth=1)
│   └── routes/
│       ├── auth_routes.py                # POST /register, POST /login
│       ├── plan.py                       # GET /plans (full content), PUT /plan (with _warnings)
│       ├── log.py                        # POST /log (body_part denorm), GET /log, DELETE /log/{id}
│       ├── crash.py                      # POST /crash, GET /crashes
│       ├── catalog.py                    # GET/POST/PUT/PATCH /exercises/* + /muscle-groups/*
│       ├── _catalog_validators.py        # Pure-Python validators (testable without app stack)
│       ├── analytics.py                  # GET /analytics/strength/{exercise-progress, body-parts, overview}
│       ├── _analytics_helpers.py         # Pure-Python: Epley 1RM, deltas, window splits, week_start
│       └── schema.py                     # GET /schema (public, per-type)
├── tools/                                # Operational scripts (mounted COPY in Dockerfile)
│   ├── bootstrap_catalog.py              # Idempotent seed of exercises + muscle_groups on startup
│   ├── backfill_log_body_parts.py        # One-shot backfill for historical workout_logs
│   └── seed_data/
│       ├── exercises.json                # 30 strength exercises (English name + aliases)
│       └── muscle_groups.json            # 20 muscle groups with antagonists + region
├── tests/                                # pytest unit + route tests (103 tests, 8 suites)
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── requirements-dev.txt                  # pytest etc.

schemas/                                  # JSON Schema docs (mounted into Docker as /schemas)
├── workout-plan.schema.json              # Strength v1 (x-schema-id: 2026-04-30T00:00:00Z)
├── cycling-plan.schema.json              # Cycling v1 (x-schema-id: 2026-04-27T00:00:00Z)
├── workout-log.schema.json               # Strength export schema
└── sample-plan.json                      # Strength sample
```

---

## 2. Data Flow

```
                Claude (AI)
                    |
                    v
           Sync Server (FastAPI + MongoDB)
                    |                              ^
                    | GET /plans                   | POST /log
                    | (full content per type)      | POST /crash
                    v                              |
              iOS App
                    |
   plan_type peek -> ParsedPlan
        |                |
        v                v
   strength branch    cycling branch
        |                |
        v                v
   SDPlan -> SDTemp.   SDCyclingPlan -> SDCyclingTemplate
        |                |
        v                v
   ActiveWorkoutVM   CyclingWorkoutVM
        |                |
        v                v
   SDWorkout +       SDCyclingWorkout +
   SDExerciseLog +   SDCyclingSegmentLog
   SDSetLog              |
        |                |
        +--> SyncService.uploadWorkout / uploadCyclingWorkout (fire-and-forget)
             SyncService.uploadCrashReport  (on next launch, if pending)
```

---

## 3. Sync Architecture

### Auth
- Email/password -> JWT (90-day sliding expiry)
- `X-Refreshed-Token` header when within 30 days of expiry
- Client stores JWT + email in Keychain
- 401 -> token cleared, user prompted to login

### Plan Sync
- `GET /plans` returns the LATEST version of each plan, in FULL.
  Body is a heterogeneous array -- each item carries its own `plan_type`.
- Client decodes to `[PlanSummary]` containing raw JSON per plan.
- `PlanSyncHelper` peeks `plan_type` and dispatches:
  - `strength` -> compare with SDPlan.planVersion, import via `importStrength`
  - `cycling`  -> compare with SDCyclingPlan.planVersion, import via `importCycling`
  - unknown    -> skipped silently (will surface after app update)

### Log Sync
- Strength workout finished: `WorkoutSyncService.uploadStrength` builds a
  `WorkoutLogJSON` envelope (`workouts: [...]`) and sends `POST /log`.
- Cycling workout finished: `WorkoutSyncService.uploadCycling` builds a
  `CyclingLogEnvelopeJSON`. Server stores both shapes in `workout_logs`.
- Failed uploads leave the local workout with `syncedAt == nil`. `WorkoutSyncService.retryPending`
  retries finished unsynced workouts on app launch, foreground activation,
  after login/register, and from the manual History swipe action.
- Swipe-to-delete on history: `SyncService.deleteWorkout(id)`.

### Exercise Catalog (analytics foundation)
- Two normalized Mongo collections: `exercises` + `muscle_groups`. Exercise documents reference muscles by slug; the catalog endpoint resolves them into embedded objects on read so consumers do not need a second hop.
- Slugs are immutable language-neutral IDs. English snake_case is convention but the slug is the primary key.
- Seeded from `tools/seed_data/{exercises,muscle_groups}.json` via `tools/bootstrap_catalog.py` on every container start (idempotent upsert by slug).
- Read endpoints public (`GET /exercises/catalog`, etc.); write endpoints JWT-authed.
- Plan exercises optionally carry `catalog_id` -> slug; missing/unknown catalog_id triggers a warning in `PUT /plan` response (`_warnings: [...]`) but is not a hard error.
- iOS preserves `catalog_id` from plan import through SwiftData (`SDExercise`), workout logs (`SDExerciseLog`), and strength JSON export. Logs also carry client-side `body_part` so analytics has a fallback for local-only plans.
- `POST /log` middleware denorms `body_part` onto each strength exercise log entry: priority is catalog (if `catalog_id` present) -> plan lookup by `(plan_id, plan_version, exercise_id)` -> none.
- Backfill script (`tools/backfill_log_body_parts.py`) covers historical logs that pre-date the middleware.

### Strength Analytics
- Server-side aggregation over `workout_logs`. Mongo pipeline does the cheap work (filter + unwind + project working sets), Python does the math (volume, Epley 1RM, deltas, weekly bins). For our scale (single user, thousands of sets at most) this is plenty fast and far easier to reason about than nested $group pipelines.
- Three endpoints, all JWT-authed:
  - `GET /analytics/strength/exercise-progress` -- per-exercise series + 30/90-day relative deltas. Group key is `catalog_id` (cross-plan continuity) with fallback to `(plan_id/exercise_id)` for older logs.
  - `GET /analytics/strength/body-parts` -- weekly volume bins per body_part + 30/90-day deltas. Uses denormed `body_part` field from log middleware.
  - `GET /analytics/strength/overview` -- top progressing exercises (by volume_pct_30d), body_part snapshot, total workouts in window. Composes the other two endpoints internally.
- **Headline metric is `volume = Σ(weight × reps)`** over working sets only. Top weight alone is dropped from analytics -- "120 kg x 1 rep" is meaningless without rep context.
- **Headline number is RELATIVE delta %**, not absolute kg×reps. Two windows side-by-side (recent N days vs prior N days), `null` when prior is empty (avoids misleading inf%).
- Pure helpers in `_analytics_helpers.py`: `epley_1rm`, `relative_delta_pct`, `split_window`, `week_start`, `workout_metrics`. 21 unit tests.
- **Deferred for separate phase:** stalled-streak detection, overreach flags, auto-progression suggestions ("insights"). MVP delivers raw numbers + charts data; UI/insights layer comes after a few weeks of accumulated data.

### Crash Reports
- `CrashReporter.install()` registers `NSSetUncaughtExceptionHandler` + signal handlers
  (SIGABRT/SEGV/BUS/ILL/TRAP/FPE/PIPE) on app start.
- On crash: writes a JSON report to `Application Support/CrashReports/<uuid>.json`,
  then re-raises with default handler (so iOS records its own crash log).
- On next launch: `CrashReporter.uploadPending()` (fire-and-forget) ships each
  pending report via `POST /crash` and removes it on success. Keeps the file
  if upload fails (no auth, no network) for the next attempt.

### Schema & Compatibility
- Each plan carries `schema` (timestamp). Server JSON Schema has matching `x-schema-id`.
- App stores `PlanSchema.id(for: type)`:
  - `strengthId` = `"2026-04-30T00:00:00Z"`
  - `cyclingId`  = `"2026-04-27T00:00:00Z"`
- Validation is structural: app checks plan_type, segment.kind / body_part, target.type / technique.
- Stored plans failing validation are shown as "not supported" with timestamps.
- PlanType -- enum on both sides: `strength`, `cycling`.

---

## 4. SwiftData Models

### Two-layer model strategy
- **Layer 1: JSON Codable structs** -- `WorkoutPlanJSON`, `CyclingPlanJSON`, ... -- 1:1 with JSON.
- **Layer 2: SwiftData @Model classes** -- `SD*` prefixed, with relationships, source of truth.

### Strength relationships
```
SDPlan (1) --> (N) SDTemplate
SDTemplate (1) --> (N) SDExerciseGroup
SDExerciseGroup (1) --> (N) SDExercise
SDExercise (1) --> (N) SDPrescribedSet

SDWorkout (1) --> (N) SDExerciseLog
SDExerciseLog (1) --> (N) SDSetLog
SDWorkout.templateId -> string FK to SDTemplate (survives re-import)
```

### Cycling relationships
```
SDCyclingPlan (1) --> (N) SDCyclingTemplate
SDCyclingTemplate (1) --> (N) SDCyclingSegment   (top-level segments)
SDCyclingSegment.parent -> SDCyclingSegment      (children of an interval_block)
SDCyclingSegment.children <- inverse of parent

SDCyclingWorkout (1) --> (N) SDCyclingSegmentLog
SDCyclingWorkout.templateId / planId -> strings (survive re-import)
SDCyclingSegmentLog.segmentPath -> path string (e.g. "block[0].rep[2].work")
                                   to match logged segments back to expanded steps
```

### Self-referential SwiftData (cycling)
`SDCyclingSegment` is self-referential: top-level segments are owned by a template
(`segment.template != nil`); children of an `interval_block` are owned by their
parent segment (`segment.parent != nil`). Exactly one of {template, parent} is set.

### Shared Base Contract
Every plan (strength or cycling):
- `plan_type` -- discriminator (`strength`, `cycling`)
- `plan_id`   -- stable slug
- `plan_version` -- monotonic integer
- `plan_name` -- display string
- `schema`    -- timestamp id of the schema it was built against
- `created_at` -- ISO 8601

---

## 5. Strength Active Workout -- State Machine

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

### TechniqueFlow
| Technique | Behavior | Timer |
|-----------|----------|-------|
| `straight`   | Sequential sets with rest | After each set |
| `drop_set`   | Working + drop (reduce weight %) | After last drop only |
| `rest_pause` | Main + short-rest continuations | 15-20s between continuations |
| `myo_reps`   | Activation + mini-sets (limited) | 5s between minis |
| `superset`   | Alternate between paired exercises | After both exercises |

Multi-pair supersets in one group: `TechniqueFlowFactory` always pairs the lowest
free index with its partner. After both exercises in a pair complete,
`advanceToNextExercise` jumps to `max(coveredIndices) + 1`. Two adjacent pairs
(e.g. v12 day-A: a4<->a6 then a5<->a9) are visited correctly. Verified by
`MultipleSupersetPairsTests.testTwoAdjacentSupersetPairsBothExecuteFully`.

---

## 6. Cycling Executor -- State Machine

```
IDLE -> RUNNING <-> PAUSED -> FINISHING -> SAVED
```

### Step expansion
On `startWorkout(plan, template)`, `CyclingExpander.expand(template)` flattens
top-level segments into a linear sequence:
- A leaf becomes one `CyclingExecStep`.
- An `interval_block` with N repeats and M children expands to N*M leaves.
- Each step gets a stable `path` string (e.g. `"block[0].rep[2].work"`)
  that goes into the per-segment log.

### Tick loop
A 1-second timer in `CyclingWorkoutView` calls `vm.tick()`:
1. Refreshes `liveBpm = hrSource.currentBpm` (so SwiftUI re-renders even when paused).
2. If running: increments `elapsedInStepSeconds`; collects HR sample if available;
   accumulates `inZoneSeconds` if the live BPM falls within target.
3. Auto-advances to next step when step duration elapses.

### HR source
`HRSourceResolver.resolve()` returns:
- `WatchHRSource` if `WCSession` is paired + Watch app installed + activated
- `NoHRSource` otherwise

`WatchHRSource` registers as `HRSampleListener` on `WorkoutSessionManager.shared`
and forwards `start/stop` to `startMirroringCardio` / `stopMirroring`. The
session manager dispatches incoming `hr_sample` events from the Watch.

### Save
On `Save`, the VM:
- Writes per-step `SDCyclingSegmentLog` (duration_actual, target min/max, avg/max HR,
  in_zone_seconds, skipped flag).
- Writes the parent `SDCyclingWorkout` (total duration, had_hr_source, avg/max HR).
- Fires `SyncService.uploadCyclingWorkout` (fire-and-forget).

---

## 7. Apple Watch Integration

### Components
- **`WorkoutSessionManager` (iOS)** -- single shared `WCSession.delegate`. Sends
  `{command: "startWorkout", activity: "strength" | "cycling"}` and
  `{command: "stopWorkout"}` to the Watch. Receives `hr_sample` events and routes
  them to a registered `HRSampleListener`.
- **`WatchWorkoutManager` (watchOS)** -- handles incoming commands, configures
  `HKWorkoutConfiguration` (`.cycling` or `.traditionalStrengthTraining`), runs
  `HKWorkoutSession` + `HKLiveWorkoutBuilder`. When `isCardioMode == true` it
  forwards each new HR sample to iPhone:
  `{event: "hr_sample", bpm: <int>, t: <unix_seconds>}`.

### Flow
```
[iPhone]                                                [Apple Watch]
CyclingWorkoutVM.startWorkout
    |
    v
HRSourceResolver.resolve -> WatchHRSource
    |
    v
WatchHRSource.start
    |
    v
WorkoutSessionManager.startMirroringCardio
    |
    v
WCSession.sendMessage  -----------------------------> didReceiveMessage
{command: startWorkout, activity: cycling}                  |
                                                            v
                                                   WatchWorkoutManager.startWorkout(activity: "cycling")
                                                            |
                                                            v
                                                   HKWorkoutSession(.cycling) +
                                                   HKLiveWorkoutBuilder
                                                            |
                                                            | HR collected
                                                            v
                                          sendHRToiPhone(bpm) via WCSession.sendMessage
                                          {event: hr_sample, bpm, t}
                                                  |
WorkoutSessionManager.didReceiveMessage  <--------+
    -> hrListener.didReceiveHRSample(bpm)
        -> WatchHRSource.currentBpm
            -> CyclingWorkoutVM.tick reads -> liveBpm
                -> SwiftUI re-renders BPM card
```

### Fallback
`isWatchAvailable` checks `WCSession.isPaired && isWatchAppInstalled &&
activationState == .activated`. False -> resolver returns `NoHRSource`,
view renders "No heart-rate source", log records `had_hr_source: false`.

---

## 8. Crash Reporting

### Capture (CrashReporter)
- `install()` is idempotent; called from `IronLogApp.init()` before anything else.
- Hooks: `NSSetUncaughtExceptionHandler` for Obj-C exceptions; `signal()` for
  POSIX signals (SIGABRT/SEGV/BUS/ILL/TRAP/FPE/PIPE).
- Inside the handler:
  1. Re-entrancy guard (`isHandling` flag).
  2. Build a `[String: Any]` report (id, created_at, app_version, app_build, os,
     device_model, kind, name, reason, stack via `Thread.callStackSymbols`).
  3. `JSONSerialization.data` -> atomic write to
     `Application Support/CrashReports/<uuid>.json`.
  4. Re-raise the signal with the default handler (so iOS still records its own
     crash log).

### Caveat
Foundation APIs (`JSONSerialization`, `Data.write`) are not async-signal-safe.
For most app crashes this works in practice; corrupted-heap crashes may not
write a report. Acceptable trade-off vs adding a pure-C reporter
(e.g. PLCrashReporter) for our use case.

### Upload
`uploadPending()` runs in a detached background `Task` from `IronLogApp.init`
after settings load. Walks the folder, ships each report via
`POST /crash` with the user's JWT, deletes only on success. Files persist if
auth/network unavailable -> retried next launch.

---

## 9. Server

### Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET    | /health         | no  | Healthcheck |
| GET    | /schema         | no  | Schema description per plan_type |
| POST   | /register       | no  | Create account -> JWT |
| POST   | /login          | no  | Login -> JWT |
| GET    | /plans          | JWT | Latest version of each plan_id, FULL content (heterogeneous) |
| PUT    | /plan           | JWT | Upload new version (validated; plan_type from body) |
| POST   | /log            | JWT | Upsert workouts (any envelope shape) |
| GET    | /log            | JWT | Query logs (since, template_id, type, limit) |
| DELETE | /log/{id}       | JWT | Delete workout log |
| POST   | /crash          | JWT | Receive crash report |
| GET    | /crashes        | JWT | List recent crash reports for current user |

### Validation pipeline
1. `validate_base(data)` -- shared base contract: plan_type, plan_id, plan_version,
   plan_name, created_at.
2. `SCHEMA_REGISTRY[plan_type].validate(data)` -- per-type structural validation.
3. Version enforcement: new `plan_version` must be > existing for that
   `(user_id, plan_type, plan_id)`.
4. Insert into `plans` collection with `user_id`.

### Tests
- `tests/test_base_validator.py` -- shared base contract.
- `tests/test_strength_validator.py` -- strength_v1 (body_part, technique, sets).
- `tests/test_cycling_validator.py` -- cycling_v1 (kinds, target, repeats/children,
  max-depth, progression).
- `tests/test_routes.py` -- FastAPI route contracts for `/plans`, `/log`, and strength analytics with an in-memory fake DB.

Run: `python -m pytest tests/` from `ironlog-server/` (with `requirements-dev.txt`).

---

## 10. Sprint History

### Sprint 1: Foundation
- XcodeGen project, JSON Codable models, SwiftData models
- PlanImportService, Plans UI (list, import, preview)
- Basic ActiveWorkout: template picker, set logging, rest timer

### Sprint 2: UX + Features
- TechniqueFlow system (straight, drop, myo, rest-pause, superset)
- Dynamic Island + Lock Screen Live Activity
- App icon, SetRoadmap, WeightStepper, Exercise list sheet
- Exercise rating + export, Workout history with swipe-delete
- max_mini_sets, warmup sets, schema documentation

### Sprint 3: Sync Server + Auth
- FastAPI + MongoDB + Docker server
- JWT auth (sliding 90-day, bcrypt)
- Shared Base Contract + Schema identification
- PlanType enum (server + client synced)
- Plan sync, log sync (fire-and-forget), Keychain storage

### Sprint 6: Strength analytics MVP (current)
- Three endpoints under `/analytics/strength/*` -- exercise-progress, body-parts, overview
- Volume + Epley est_1rm metrics; relative deltas over 30/90-day windows; weekly bins for body parts
- Cross-plan grouping via catalog_id with `(plan_id/exercise_id)` fallback
- Pure-Python helpers (`_analytics_helpers.py`) with 21 unit tests
- Defensive doc normalization for old logs missing the catalog_id / body_part fields
- Total server tests: 103 across 8 suites

### Sprint 5: Exercise catalog + analytics foundation
- Mongo collections: `exercises` (30 seed) + `muscle_groups` (20 seed), normalized
- Slug as immutable language-neutral ID; English-only `name`/`aliases` (model translates user input)
- `tools/bootstrap_catalog.py` -- idempotent seed on every container start
- `app/routes/catalog.py` + `_catalog_validators.py` -- read + write endpoints with pure-Python validation layer
- Plan schema bump (`x-schema-id: 2026-04-30T00:00:00Z`) -- optional `catalog_id` on Exercise
- `strength_v1.collect_warnings()` -- soft validation for missing/unknown `catalog_id`; surfaces as `_warnings` in `PUT /plan` response (no 422)
- `POST /log` body_part denorm middleware + `tools/backfill_log_body_parts.py` for historical logs
- Catalog pytest coverage for seed sanity, warnings logic, and write-payload validation
- Indexes added on `workout_logs` for analytics: `(user_id, plan_type, started_at)`, `(user_id, exercises.exercise_id)`, `(user_id, exercises.catalog_id)`, `(user_id, exercises.body_part)`
- iOS PlanSchema.strengthId bumped to match; `catalog_id` is preserved client-side and exported in strength logs

### Sprint 4: Cycling + Watch HR + Crashes
- New plan type: `cycling` with segments + interval_block + target HR / RPE / free
- `CyclingExpander` flattens nested blocks for execution
- New SwiftData hierarchy: `SDCyclingPlan` / `Template` / `Segment` / `Workout` / `SegmentLog`
- `ParsedPlan` enum + `plan_type` peek in import; `GET /plans` returns full content
- `CyclingWorkoutView` executor with timer, target card, controls
- Apple Watch HR live streaming for cardio workouts (Phase 2):
  `WCSession` activity routing, `HKLiveWorkoutBuilder` HR forwarding
- Crash reporting: `CrashReporter` + `POST /crash` + `GET /crashes`
- Tests: iOS XCTest (4 suites, 24 tests) + server pytest (8 suites, 103 tests)
