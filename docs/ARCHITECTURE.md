# IronLog — Workout Tracker iOS App
## Architecture Document (MVP)

**Date:** 2026-03-26
**Target:** iOS 17+, Swift, SwiftUI, SwiftData
**Pattern:** MVVM + Services

---

## 1. Project Structure

```
IronLog/
├── IronLogApp.swift                 # Entry point, SwiftData container setup
├── ContentView.swift                # Tab-based root navigation
│
├── Models/
│   ├── JSON/                        # Codable structs for import/export (mirror JSON schemas)
│   │   ├── WorkoutPlanJSON.swift     # Import schema types
│   │   └── WorkoutLogJSON.swift      # Export schema types
│   │
│   └── Data/                        # SwiftData @Model classes (persistence)
│       ├── SDPlan.swift              # Stored workout plan
│       ├── SDTemplate.swift          # Stored template (training day)
│       ├── SDExerciseGroup.swift     # Muscle group container
│       ├── SDExercise.swift          # Exercise definition
│       ├── SDPrescribedSet.swift     # Prescribed set from plan
│       ├── SDWorkout.swift           # Completed workout session
│       ├── SDExerciseLog.swift       # Logged exercise within workout
│       └── SDSetLog.swift            # Logged individual set
│
├── Services/
│   ├── PlanImportService.swift       # JSON parsing, validation, SwiftData persistence
│   ├── WorkoutExportService.swift    # Build export JSON from SwiftData
│   └── RestTimerService.swift        # Countdown timer with haptics
│
├── ViewModels/
│   ├── PlansViewModel.swift          # Plan list, import flow
│   ├── ActiveWorkoutViewModel.swift  # Core workout session logic
│   └── HistoryViewModel.swift        # Workout history, export
│
├── Views/
│   ├── Plans/
│   │   ├── PlansListView.swift       # List of imported plans
│   │   ├── ImportView.swift          # Paste JSON / pick file
│   │   └── PlanPreviewView.swift     # Preview before confirming import
│   │
│   ├── Workout/
│   │   ├── TemplatePicker.swift      # Choose Day A / Day B
│   │   ├── ActiveWorkoutView.swift   # Main workout screen
│   │   ├── ExerciseCard.swift        # Single exercise with sets
│   │   ├── SetRowView.swift          # One set row: weight, reps, RPE/RIR inputs
│   │   ├── SupersetGroupView.swift   # Visual grouping for supersets
│   │   ├── DropSetGroupView.swift    # Visual grouping for drop sets
│   │   ├── MyoRepsGroupView.swift    # Myo-reps activation + mini sets
│   │   ├── RestPauseGroupView.swift  # Rest-pause visual
│   │   └── RestTimerView.swift       # Floating/overlay countdown timer
│   │
│   ├── History/
│   │   ├── HistoryListView.swift     # Chronological workout list
│   │   ├── WorkoutDetailView.swift   # Drill into completed workout
│   │   └── ExportView.swift          # Export period picker + actions
│   │
│   └── Components/
│       ├── NumberPad.swift           # Custom numeric input (big tap targets)
│       ├── WeightInput.swift         # Weight entry with +/- steppers
│       ├── RepsInput.swift           # Reps entry
│       └── RPEPicker.swift           # RPE/RIR selector
│
└── Utilities/
    ├── HapticManager.swift           # Haptic feedback wrapper
    └── Extensions.swift              # Date formatting, etc.
```

---

## 2. Data Flow

```
JSON Plan (from Claude) → PlanImportService → SwiftData Store
SwiftData Store → ActiveWorkoutViewModel → UI (log sets)
SDWorkout logs → WorkoutExportService → JSON (clipboard/share)
```

---

## 3. SwiftData Models — Design Decisions

### Two-layer model strategy
- **Layer 1: JSON Codable structs** — pure value types, 1:1 mirror of JSON schemas, no SwiftData deps
- **Layer 2: SwiftData @Model classes** — prefixed with `SD`, relationships via SwiftData, source of truth

### Weight prefill strategy
- Each PrescribedSet may have optional `weight_kg` (integer, from plan)
- First workout: weight pre-filled from plan's `weight_kg`
- Subsequent workouts: weight copied from previous workout's same exercise/set
- Fallback chain: previous workout -> plan -> empty (user enters manually)

### Key relationships
```
SDPlan (1) ──→ (N) SDTemplate
SDTemplate (1) ──→ (N) SDExerciseGroup
SDExerciseGroup (1) ──→ (N) SDExercise
SDExercise (1) ──→ (N) SDPrescribedSet

SDWorkout (1) ──→ (N) SDExerciseLog
SDExerciseLog (1) ──→ (N) SDSetLog
SDWorkout.templateId → string FK to SDTemplate (survives re-import)
SDExerciseLog.exerciseId → string FK to SDExercise (survives re-import)
```

---

## 4. Active Workout — State Machine

```
IDLE → ACTIVE → LOGGING_SET → REST_TIMER → LOGGING_SET → ... → FINISHING → SAVED
```

### Technique-specific behavior

| Technique | Timer behavior | Visual |
|-----------|---------------|--------|
| `straight` | Timer after each set | Standard rows |
| `drop_set` | Timer after last drop only | Grouped: working + drop indented |
| `rest_pause` | Short timer (15-20s) between continuations | Grouped with continuation markers |
| `myo_reps` | 5s between minis, full timer after last | Activation + dynamic mini rows |
| `superset` | Timer after completing both exercises | Paired exercises in bracket |

---

## 5. Implementation Plan

### Sprint 1: Foundation
- Xcode project, JSON Codable models, SwiftData models, PlanImportService, Plans UI

### Sprint 2: Active Workout (core)
- TemplatePicker, ActiveWorkoutViewModel, ExerciseCard, SetRowView, RestTimer

### Sprint 3: Technique types
- SupersetGroup, DropSetGroup, MyoRepsGroup, RestPauseGroup, RPE/RIR input

### Sprint 4: History + Export
- HistoryList, WorkoutDetail, previous workout lookup, ExportService, ExportView

### Sprint 5: Polish
- Session RPE, notes, haptics, edge cases, dark mode
