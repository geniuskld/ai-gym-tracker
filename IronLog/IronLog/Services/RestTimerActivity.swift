import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Activity Attributes

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "performing" or "resting"
        var phase: String
        /// Timer reference date (start for performing, end for resting)
        var timerDate: Date
        /// Whether rest has exceeded the limit
        var isOvertime: Bool
        /// Current weight in kg (performing phase)
        var weightKg: Double?
        /// Exercise name (updated per set)
        var exerciseName: String
        /// Next set label
        var nextSetLabel: String
    }

    /// Total rest duration in seconds (for progress calculation)
    let totalRestSeconds: Int
}

// MARK: - Live Activity Manager

@MainActor
final class RestTimerActivityManager {

    static let shared = RestTimerActivityManager()
    private var currentActivity: Activity<RestTimerAttributes>?

    private init() {}

    /// Start or update to performing phase
    func startPerforming(
        exerciseName: String,
        weightKg: Double?
    ) {
        let state = RestTimerAttributes.ContentState(
            phase: "performing",
            timerDate: .now,
            isOvertime: false,
            weightKg: weightKg,
            exerciseName: exerciseName,
            nextSetLabel: ""
        )

        if let activity = currentActivity {
            // Update existing activity
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = RestTimerAttributes(totalRestSeconds: 0)
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {}
        }
    }

    /// Switch to resting phase
    func startResting(
        exerciseName: String,
        nextSetLabel: String,
        totalSeconds: Int
    ) {
        let state = RestTimerAttributes.ContentState(
            phase: "resting",
            timerDate: Date.now.addingTimeInterval(TimeInterval(totalSeconds)),
            isOvertime: false,
            weightKg: nil,
            exerciseName: exerciseName,
            nextSetLabel: nextSetLabel
        )

        if let activity = currentActivity {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = RestTimerAttributes(totalRestSeconds: totalSeconds)
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {}
        }
    }

    func markOvertime() {
        guard let activity = currentActivity else { return }
        let prev = activity.content.state
        let state = RestTimerAttributes.ContentState(
            phase: "resting",
            timerDate: .now,
            isOvertime: true,
            weightKg: nil,
            exerciseName: prev.exerciseName,
            nextSetLabel: prev.nextSetLabel
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func endIfNeeded() {
        let state = RestTimerAttributes.ContentState(
            phase: "resting",
            timerDate: .now,
            isOvertime: false,
            weightKg: nil,
            exerciseName: "",
            nextSetLabel: ""
        )
        let activityToEnd = currentActivity
        let currentId = activityToEnd?.id
        let lingeringActivities = Activity<RestTimerAttributes>.activities
        Task {
            if let activityToEnd {
                await activityToEnd.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            for activity in lingeringActivities where activity.id != currentId {
                await activity.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
        currentActivity = nil
    }
}
