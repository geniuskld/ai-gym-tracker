# IronLog -- Workout Tracker iOS App
## Architecture Document

**Updated:** 2026-03-30
**Target:** iOS 17+, Swift, SwiftUI, SwiftData
**Pattern:** MVVM + Services
**Build:** XcodeGen (project.yml -> xcodeproj)

---

## 1. Project Structure

```
IronLog/
├── IronLogApp.swift                 # Entry point, SwiftData container setup
├── ContentView.swift                # Tab-based root: Plans / Active Workout / History
│
├── Models/
│   ├── JSON/                        # Codable structs for import/export
│   │   ├── WorkoutPlanJSON.swift    # Import schema types
│   │   └── WorkoutLogJSON.swift     # Export schema types (with exerciseRating, planName)
│   │
│   └── Data/                        # SwiftData @Model classes (SD* prefix)
│       ├── SDPlan.swift             # Stored workout plan
│       ├── SDTemplate.swift         # Training day template
│       ├── SDExerciseGroup.swift    # Muscle group container
│       ├── SDExercise.swift         # Exercise definition (incl. maxMiniSets)
│       ├── SDPrescribedSet.swift    # Prescribed set (type, reps, weightKg, rir, weightPercentDrop)
│       ├── SDWorkout.swift          # Completed workout session (incl. planName)
│       ├── SDExerciseLog.swift      # Logged exercise (incl. exerciseRating)
│       └── SDSetLog.swift           # Logged individual set
│
├── Services/
│   ├── PlanImportService.swift      # JSON parsing, validation, SwiftData persistence
│   ├── WorkoutExportService.swift   # Build export JSON from SwiftData models
│   ├── RestTimerService.swift       # Countdown timer with haptics, notifications, Live Activity
│   └── RestTimerActivity.swift      # ActivityKit: RestTimerAttributes + RestTimerActivityManager
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
│   │   ├── PlansListView.swift      # List of imported plans
│   │   ├── ImportView.swift         # Paste JSON / pick file
│   │   └── PlanPreviewView.swift    # Preview before confirming import
│   │
│   ├── Workout/
│   │   ├── TemplatePicker.swift     # Choose Day A / Day B
│   │   ├── ActiveWorkoutView.swift  # Main workout screen (all phases)
│   │   └── DebugLogView.swift       # Debug: view raw set data during workout
│   │
│   └── History/
│       └── WorkoutHistoryView.swift # List + detail + swipe-delete + ShareLink export
│
├── Utilities/
│   └── Extensions.swift             # Date formatting, etc.
│
└── Resources/
    ├── Assets.xcassets/             # App icon (bicep+brain), AccentColor
    └── sample-plan.json             # Bundled example plan for first launch

IronLogWidgets/                      # Widget extension target (Live Activity UI)
├── Info.plist                       # NSExtension with widgetkit-extension point
├── IronLogWidgetsBundle.swift       # @main WidgetBundle
└── RestTimerLiveActivity.swift      # Dynamic Island + Lock Screen Live Activity views
```

---

## 2. Data Flow

```
JSON Plan (from AI)
    |
    v
PlanImportService --> SwiftData Store (SDPlan -> SDTemplate -> SDExercise -> SDPrescribedSet)
    |
    v
ActiveWorkoutViewModel
    |-- builds ExerciseState[] + SetState[] from SDTemplate
    |-- creates TechniqueFlow via TechniqueFlowFactory
    |-- manages SetPhase: ready -> performing -> enterReps -> resting -> ratingExercise
    |-- updates Live Activity (performing / resting / overtime)
    |
    v
SDWorkout + SDExerciseLog + SDSetLog (persisted to SwiftData)
    |
    v
WorkoutExportService --> JSON (Share Sheet / clipboard)
```

---

## 3. SwiftData Models -- Design Decisions

### Two-layer model strategy
- **Layer 1: JSON Codable structs** -- pure value types, 1:1 mirror of JSON schemas, no SwiftData deps
- **Layer 2: SwiftData @Model classes** -- prefixed with `SD`, relationships via SwiftData, source of truth

### Weight prefill strategy
- Each PrescribedSet may have optional `weight_kg` (integer, from plan)
- Each set in a plan can have its own weight (e.g., warmup 40, warmup 70, working 100)
- First workout: weight pre-filled from plan's `weight_kg`
- Subsequent workouts: weight copied from previous workout's same exercise/set
- Fallback chain: previous workout -> plan -> empty (user enters manually)
- readySlideRight only applies lastCompletedWeight when the set has no prescribed weight

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

## 4. Active Workout -- State Machine

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
  |          |
  v          v
setWeight  enterReps (manual reps entry)
```

- **ready**: shows SetRoadmap, slide right = start, slide left = set weight
- **performing**: stopwatch running, Live Activity shows weight + timer
- **enterReps**: manual reps input if not using prescribed
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

| Technique | Behavior | Flow |
|-----------|----------|------|
| `straight` | Sequential sets with rest | StraightFlow: next incomplete set, carry last working weight |
| `drop_set` | Working + drop (reduce weight %) | DropSetFlow: working -> drops with calculated weight |
| `rest_pause` | Main set + short-rest continuations | RestPauseFlow: main set -> continuations at same weight |
| `myo_reps` | Activation + mini-sets (limited) | MyoRepsFlow: activation -> minis (max N, stop if reps < 3) |
| `superset` | Alternate between paired exercises | SupersetFlow: A1 -> A2 -> rest -> A1 -> A2 -> ... |

---

## 5. Dynamic Island + Live Activity

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

### Integration
- `beginPerforming()` -> `RestTimerActivityManager.startPerforming()`
- `startRest()` -> `RestTimerActivityManager.startResting()` (via RestTimerService)
- `enterOvertime()` -> `RestTimerActivityManager.markOvertime()`
- `reset()` / `stop()` -> `RestTimerActivityManager.endIfNeeded()`

---

## 6. UI Components (ActiveWorkoutView)

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

## 7. Sprint History

### Sprint 1: Foundation (completed)
- Xcode project (XcodeGen), JSON Codable models, SwiftData models
- PlanImportService, Plans UI (list, import, preview)
- Basic ActiveWorkout: template picker, set logging, rest timer

### Sprint 2: UX + Features (completed)
- TechniqueFlow system (straight, drop, myo, rest-pause, superset)
- Dynamic Island + Lock Screen Live Activity
- App icon (golden bicep with blue brain)
- SetRoadmap replacing "1/5" badge
- Exercise list sheet with progress
- WeightStepper (-5/-1/+1/+5 buttons)
- Exercise rating (Heavy/OK/Easy) + export
- Workout history: swipe-delete, ShareLink export, planName
- max_mini_sets for myo-reps
- Warmup sets support
- Schema documentation
- Bug fixes: weight override, effort labels, flow instructions

### Sprint 3: Planned
- Periodization (auto rep-scheme by week)
- Progress analytics (weight/volume graphs)
- Auto weight recommendations from history
- Russian localization
- AI analysis integration
- Apple Watch companion (stretch)
