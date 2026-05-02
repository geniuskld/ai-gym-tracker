# AGENTS.md -- Project Context for Codex

## Project: IronLog (ai-gym-tracker)
iOS workout tracker (strength + cycling) + sync server. AI-assisted training:
Codex generates plans, app executes, logs sync back for analysis.

## Repo Structure
- `IronLog/` -- iOS app (Swift, SwiftUI, SwiftData, XcodeGen)
  - `IronLog/IronLog/` -- main app (iOS)
  - `IronLog/IronLogWidgets/` -- Live Activity / Dynamic Island
  - `IronLog/IronLogWatch/` -- watchOS app (HR streaming)
  - `IronLog/IronLogTests/` -- XCTest suites
- `ironlog-server/` -- sync server (Python, FastAPI, MongoDB, Docker)
  - `ironlog-server/tests/` -- pytest suites for validators
- `schemas/` -- JSON schema docs (mounted into Docker as /schemas)
- `docs/` -- ARCHITECTURE.md, SPEC.md

## Key Decisions
- **iOS 17+, watchOS 10+**, Swift, SwiftUI, SwiftData (NOT CoreData)
- **MVVM + Services** pattern
- **No manual plan creation** in UI -- JSON import only (from AI or server)
- **Two-layer models**: JSON Codable structs (parsing) + SwiftData @Model (persistence)
- SwiftData models prefixed with `SD` to avoid naming conflicts
- **String foreign keys** between workouts and templates (survives re-import)
- **XcodeGen**: project.yml generates xcodeproj
- **Shared base contract**: plan_type + plan_id + plan_version + plan_name + schema (timestamp) + created_at
- **PlanType enum**: server (Python Enum) and client (Swift enum) must stay in sync.
  Currently: `strength`, `cycling`.
- **Schema identification**: each plan carries `schema` field (timestamp).
  App has `PlanSchema.id(for: type)` constants per plan type.
- **Plan import auto-dispatch**: `PlanImportService.parse(data)` peeks `plan_type`
  and returns a `ParsedPlan` enum (`.strength(WorkoutPlanJSON)` or `.cycling(CyclingPlanJSON)`).

## Sync Architecture
- Server: FastAPI + MongoDB + Docker (`ironlog-server/`)
- Auth: email/password -> JWT (90-day sliding expiry, X-Refreshed-Token header)
- Client stores JWT in Keychain, email in Keychain
- Default server URL: `http://v170184.hosted-by-vdsina.com:8844`
- **Plan sync**: `GET /plans` returns FULL content of latest version of each plan_id
  (heterogeneous array). `PlanSyncHelper` peeks `plan_type` per item and dispatches
  to strength or cycling import.
- **Log upload**: fire-and-forget after workout finish. Strength uses `WorkoutLogJSON`
  envelope; cycling uses `CyclingLogEnvelopeJSON`. Server stores both shapes.
- **Log delete**: fire-and-forget on swipe-to-delete in history.
- **Crash reports**: `CrashReporter` writes JSON to disk on crash; `IronLogApp.init`
  ships pending reports via `POST /crash` on next launch.

## Plan Schema & Compatibility
- Each plan carries `schema` field -- timestamp identifier of the schema used to create it
- Server JSON schema has `x-schema-id` with the same timestamp; Codex copies it into the plan
- App has `PlanSchema.strengthId` / `PlanSchema.cyclingId` constants
- **Validation is structural**: app checks plan_type, segment kinds (cycling) /
  body_part+technique (strength), required fields
- If stored plan doesn't pass validation -> "not supported" with schema timestamps
- If server plan can't be decoded -> skip silently (will surface after app update)
- Server rejects unknown plan_type (422)

## Server Endpoints
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET    | /health   | no  | Healthcheck |
| GET    | /schema   | no  | Schema description per plan_type |
| POST   | /register | no  | Create account -> JWT |
| POST   | /login    | no  | Login -> JWT |
| GET    | /plans    | JWT | Latest version of each plan, FULL content (polymorphic) |
| PUT    | /plan     | JWT | Upload new version. Response includes `_warnings: [...]` when soft validation finds issues (e.g. missing `catalog_id`). |
| POST   | /log      | JWT | Upsert workout logs (envelope `{workouts: [...]}`). Strength logs are denormed: each exercise entry gets `body_part` resolved at write time from catalog or plan. |
| GET    | /log      | JWT | Query logs (since, template_id, type, limit) |
| DELETE | /log/{id} | JWT | Delete workout log |
| POST   | /crash    | JWT | Receive crash report |
| GET    | /crashes  | JWT | List recent crash reports for current user |
| GET    | /exercises/catalog            | no  | List exercises (filter `?plan_type=strength`, `?include_deprecated=true`). Muscle slugs resolved into embedded objects. |
| GET    | /exercises/{slug}             | no  | Single exercise with resolved muscles. |
| POST   | /exercises/catalog            | JWT | Add a new exercise (validates muscle slug existence). |
| PUT    | /exercises/{slug}             | JWT | Update mutable fields (slug itself immutable -- to rename, deprecate + create). |
| PATCH  | /exercises/{slug}/deprecate   | JWT | Soft-delete with optional `replaced_by`. |
| GET    | /muscle-groups                | no  | List muscle groups (filter `?region=legs`). |
| GET    | /muscle-groups/{slug}         | no  | Single muscle group. |
| POST   | /muscle-groups                | JWT | Add a new muscle group. |
| PUT    | /muscle-groups/{slug}         | JWT | Update mutable fields. |
| GET    | /analytics/strength/exercise-progress | JWT | Per-exercise series + 30/90-day deltas (volume + est_1rm). Group key: catalog_id, fallback to (plan_id/exercise_id). Optional `?since=ISO`, `?plan_id=X`. |
| GET    | /analytics/strength/body-parts        | JWT | Weekly volume per body_part + 30/90-day deltas. Optional `?weeks=N` (default 12), `?plan_id=X`. |
| GET    | /analytics/strength/overview          | JWT | Top progressing (by volume_pct_30d), body_part summary, total workouts in window. Optional `?weeks=N`, `?plan_id=X`. |

Note: `GET /plan` and `GET /plan/versions` were removed -- `/plans` returns full content now.

## Plan Types

### Strength
- Structure: `templates -> groups -> exercises -> sets`
- Schema: `schemas/workout-plan.schema.json` (`x-schema-id`: `2026-04-30T00:00:00Z`)
- Techniques: straight, drop_set, rest_pause, myo_reps, superset
- Multiple superset pairs in one group are supported (verified by tests)
- Each exercise SHOULD include `catalog_id` (slug from `/exercises/catalog`) for analytics continuity. Server emits a soft warning when missing or unknown.

### Cycling
- Structure: `templates -> segments` (with optional `interval_block` containing children)
- Schema: `schemas/cycling-plan.schema.json` (`x-schema-id`: `2026-04-27T00:00:00Z`)
- Segment kinds: warmup, work, recovery, cooldown, steady, interval_block
- Targets: `hr_bpm_range`, `rpe`, `free`
- `interval_block`: max nesting depth = 1 (block cannot contain block)
- Optional `progression { axis, step, advance_when }` -- hint for next plan version

## Strength Technique Types
| Technique | Timer | Behavior |
|-----------|-------|----------|
| straight  | After each set | Standard sequential |
| drop_set  | After last drop only | Working + drops with weight % reduction |
| rest_pause| 15-20s between continuations | Main set + continuations at same weight |
| myo_reps  | 5s between minis | Activation + dynamic mini rows (max_mini_sets) |
| superset  | After both exercises | Paired A1 -> A2 alternating |

## Exercise Catalog (cross-plan analytics)
- Server-side mongo collections: `exercises` + `muscle_groups` (normalized).
- Seeded on every container start from `tools/seed_data/{exercises,muscle_groups}.json` (idempotent upsert by slug; user edits via API survive restarts).
- Initial seed: 30 exercises + 20 muscle groups.
- **Slug = immutable language-neutral ID.** English snake_case is convention, but the slug is the primary key. Never renamed; if an exercise needs reinterpreting, deprecate + create new with optional `replaced_by`.
- **Stability rules:**
  - `(plan_id, exercise_id)` is stable across versions of the same plan when it identifies the same physical exercise.
  - `catalog_id` (slug) is stable across plans -- when one exercise appears in two different plans, it MUST share the catalog_id so analytics tracks one progression line.
  - For now `catalog_id` is OPTIONAL (warning, not 422); will become required once all production plans carry it.
- **Naming convention** for new slugs: `<movement>_<equipment>_<modifier?>` lowercase, e.g. `incline_bench_press_barbell`, `cable_triceps_pushdown_rope`.
- **AI plan-author flow:** before generating a plan, fetch `GET /exercises/catalog?plan_type=strength`. Match user phrases against `name` + `aliases` (English-only -- model translates user input first). New exercise needed -> propose slug + ASK USER before POST'ing to catalog.
- **Aliases are English-only.** Model handles translation. We don't maintain multilingual lists.
- **body_part denorm at log write:** `POST /log` enriches each strength exercise log entry with `body_part` (from catalog if `catalog_id` present, else plan lookup). Backfill script `tools/backfill_log_body_parts.py` covers historical logs.

## Analytics (strength only, MVP)
- Server-side aggregation over `workout_logs` (filtered to `plan_type: "strength"` + working sets only).
- **Core metrics:** `volume = Σ(weight × reps)`, `est_1rm = max Epley` (weight × (1 + reps / 30)). Volume is the headline -- top weight alone is meaningless without rep context.
- **Headline numbers are RELATIVE deltas** (`%`), not absolutes -- "грудь +10% за месяц" lands better than "5400 kg × reps". Compute via 30/90-day windows, returning `null` when there is no prior window data (avoids misleading inf%).
- **Group key for cross-plan continuity:** `catalog_id` if present in the log, else `(plan_id/exercise_id)` fallback. When all production plans carry catalog_id, the fallback path goes away naturally.
- **Helpers:** `app/routes/_analytics_helpers.py` -- pure-Python (epley_1rm, relative_delta_pct, split_window, week_start, workout_metrics). 21 unit tests cover edge cases.
- **Deferred (separate phase, "insights"):** stalled-streak detection, overreach flags, automated next-version suggestions. For now we deliver raw graphs only.
- Cycling analytics not yet started -- needs a few weeks of cycling logs first.

## Apple Watch Integration
- Strength: `traditionalStrengthTraining` workout session, no HR forwarding
- Cycling: `.cycling` workout session, HR samples forwarded to iPhone via WCSession
- iPhone executor displays live BPM with color (green=in zone, red=out of zone)
- Without watch: timer-only, log records `had_hr_source: false`
- Routing: `WorkoutSessionManager` (iPhone) <-> `WatchWorkoutManager` (watchOS)

## Crash Reporting
- `CrashReporter.install()` in `IronLogApp.init` before anything else
- Captures: `NSException` + signal handlers (SIGABRT/SEGV/BUS/ILL/TRAP/FPE/PIPE)
- Writes JSON to `Application Support/CrashReports/<uuid>.json`
- Re-raises with default handler so iOS records its own crash log too
- On next launch: ship pending reports via `POST /crash`, delete on success
- Caveat: Foundation APIs aren't async-signal-safe; corrupted-heap crashes may not write

## Build
```bash
# iOS
cd IronLog && xcodegen generate && open IronLog.xcodeproj

# Server
cd ironlog-server && docker compose up --build -d
```

## Tests
```bash
# iOS
cd IronLog
xcodebuild -project IronLog.xcodeproj -scheme IronLog \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' test

# Server (requires venv with pytest)
cd ironlog-server
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest tests/
```

Test inventory:
- iOS: 4 suites, 13 tests (`MultipleSupersetPairsTests`, `CyclingExpanderTests`,
  `ParsedPlanDispatchTests`, `CrashReporterTests`)
- Server: 8 suites, 103 tests (`test_base_validator`, `test_strength_validator`,
  `test_cycling_validator`, `test_catalog_seed`, `test_strength_warnings`,
  `test_catalog_validation`, `test_analytics_helpers`, `test_routes`)

## Server Deploy
SSH access: `root@v170184.hosted-by-vdsina.com` (password in shared notes).
- Server lives at `/opt/ironlog/`.
- `docker compose up --build -d` rebuilds and restarts.
- Schema files in `/opt/ironlog/schemas/` are mounted read-only into the container.

## User Context
- Based in Russia (Kaliningrad)
- Training at gym "Albatros South"
- Spinal curvature -- no axial loading
- 30 min bike before strength, 2x/week full body strength
- Norwegian 4x4 cycling protocol with progressive adaptation
- Communicate in Russian
