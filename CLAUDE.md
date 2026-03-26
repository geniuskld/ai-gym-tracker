# CLAUDE.md — Project Context for Claude Code

## Project: IronLog (ai-gym-tracker)
iOS workout tracker with JSON-based plan import/export for AI-assisted training.

## Key Decisions
- **iOS 17+**, Swift, SwiftUI, SwiftData (NOT CoreData)
- **MVVM + Services** pattern
- **No manual plan creation** in UI — JSON import only
- **Two-layer models**: JSON Codable structs (parsing) + SwiftData @Model (persistence)
- SwiftData models prefixed with `SD` to avoid naming conflicts
- **String foreign keys** between workouts and templates (survives re-import)

## MVP Scope
- Import JSON plan (clipboard / file picker)
- Validate against schema
- Template picker → Active Workout screen
- Log sets: weight (kg), reps, RPE/RIR (optional)
- Show previous workout data alongside current
- Visual grouping: supersets, drop sets, myo-reps, rest-pause
- Rest timer with haptics
- Workout history
- Export JSON log (clipboard / Share Sheet)

## NOT in MVP
- PR tracking, progress charts, HealthKit, Apple Watch
- Plan editor, cardio block, muscle map

## Architecture
See `docs/ARCHITECTURE.md` for full details:
- Project structure, data flow, state machine
- SwiftData relationships
- Implementation plan (5 sprints)

## JSON Schemas
- `schemas/workout-plan.schema.json` — import format
- `schemas/workout-log.schema.json` — export format
- `schemas/sample-plan.json` — sample plan "Альбатрос Юг"

## Technique Types (critical for Active Workout UI)
| Technique | Timer | Visual |
|-----------|-------|--------|
| straight | After each set | Standard rows |
| drop_set | After last drop only | Working + drop indented |
| rest_pause | 15-20s between continuations | Grouped with markers |
| myo_reps | 5s between minis | Activation + dynamic mini rows |
| superset | After both exercises | Paired in bracket |

## Build Order (Sprint 1 first)
1. Xcode project, JSON Codable models, SwiftData models
2. PlanImportService (parse + validate + persist)
3. PlansListView + ImportView + PlanPreviewView
4. TemplatePicker + ActiveWorkoutViewModel
5. ExerciseCard + SetRowView + rest timer
6. Technique-specific views (superset, drop, myo, rest-pause)
7. RPE/RIR input
8. History + Export

## User Context
- User is based in Russia (Kaliningrad)
- Training at gym "Альбатрос Юг"
- Has spinal curvature — no axial loading exercises
- 30 min bike before strength training
- Trains 2x/week full body
- Communicate in Russian when possible
