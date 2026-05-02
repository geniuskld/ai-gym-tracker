import ActivityKit
import Foundation
import SwiftUI

// MARK: - Schedule entry

/// One segment in the workout's pre-computed timeline. The Live Activity
/// payload carries the full list, so the widget can pick the "current"
/// segment by comparing `endsAt` to `Date.now` -- no app code required at
/// transition moments. SwiftUI re-renders when its `Text(timerInterval:)`
/// crosses an `endsAt`, naturally advancing to the next segment.
public struct ScheduledSegment: Codable, Hashable, Identifiable {
    public let stepIndex: Int       // 0-based position in the workout
    public let stepName: String     // display name (Russian, from plan)
    public let stepKind: String     // warmup | work | recovery | cooldown | steady
    public let endsAt: Date         // absolute wall-clock end-time

    public var id: Int { stepIndex }
}

// MARK: - Activity Attributes

/// Live Activity payload for a cycling workout.
///
/// Key design choice: we ship the **entire workout schedule** (every
/// segment's absolute end-time) in the content state, not just the
/// current segment. The widget self-advances by comparing `endsAt`
/// values to `Date.now`. This lets the Dynamic Island / Lock Screen
/// stay correct even when the host app has been suspended for a long
/// time (e.g. user is in YouTube for 30 minutes).
struct CyclingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Full timeline. The widget picks `current` as
        /// `first(where: $0.endsAt > Date.now)`.
        var schedule: [ScheduledSegment]

        /// When `true` the widget freezes the countdown and shows
        /// "Paused". On resume the host pushes a NEW schedule with all
        /// `endsAt` shifted forward by the paused duration, so the
        /// widget rejoins seamlessly.
        var paused: Bool
    }

    /// Static across the workout.
    let totalSteps: Int
    let workoutName: String
}

// MARK: - Activity Manager

/// Singleton wrapping ActivityKit lifecycle for a cycling Live Activity.
@MainActor
final class CyclingActivityManager {

    static let shared = CyclingActivityManager()
    private var currentActivity: Activity<CyclingActivityAttributes>?

    private init() {}

    /// Start the Live Activity with the given full schedule.
    /// Idempotent: if an activity is already running it pushes an update
    /// instead of requesting a new one.
    func start(
        workoutName: String,
        totalSteps: Int,
        schedule: [ScheduledSegment]
    ) {
        let state = CyclingActivityAttributes.ContentState(
            schedule: schedule,
            paused: false
        )
        if let activity = currentActivity {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = CyclingActivityAttributes(
                totalSteps: totalSteps,
                workoutName: workoutName
            )
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // ActivityKit may refuse if user disabled Live Activities;
                // workout continues without it.
            }
        }
    }

    /// Push a freshly computed schedule (used after pause/resume/skip).
    func updateSchedule(_ schedule: [ScheduledSegment]) {
        guard let activity = currentActivity else { return }
        let state = CyclingActivityAttributes.ContentState(
            schedule: schedule,
            paused: false
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// Flip the paused flag. The schedule is left as-is until resume,
    /// at which point the caller should push a shifted schedule via
    /// `updateSchedule`.
    func setPaused(_ paused: Bool) {
        guard let activity = currentActivity else { return }
        let prev = activity.content.state
        let state = CyclingActivityAttributes.ContentState(
            schedule: prev.schedule,
            paused: paused
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}
