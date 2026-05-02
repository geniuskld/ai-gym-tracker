# IronLog -- Roadmap

## Active

### Phase 1: watchOS mirrored workout session

**Goal:** Minimal watchOS target that accepts mirrored HKWorkoutSession from iPhone app. When user starts a workout in IronLog, Apple Watch automatically shows live workout UI with heart rate, calories, timer. No standalone watch app logic -- just a delegate that handles mirrored session from iOS 17+ HKWorkoutSession.

**Scope:**
- Add watchOS target to project.yml (XcodeGen)
- Start/stop HKWorkoutSession in ActiveWorkoutViewModel
- Minimal watchOS extension delegate (~20 lines) accepting mirrored session
- HealthKit entitlements for watchOS target
- No watch UI needed -- system provides standard workout screen

**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD

## Backlog

(empty)
