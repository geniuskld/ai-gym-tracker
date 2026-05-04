import Foundation
import UIKit
import UserNotifications

/// Schedules local notifications at each segment boundary of a cycling
/// workout so the user is alerted (banner + sound) even when the iPhone
/// is in another app -- e.g. YouTube during the warmup. Re-scheduled on
/// pause/resume/skip; cancelled on workout end.
@MainActor
enum CyclingNotificationScheduler {

    /// Identifier prefix so we can find/cancel only our requests.
    private static let prefix = "cycling-segment-"

    /// Schedules notifications for every remaining segment boundary.
    /// - Parameters:
    ///   - steps: full expanded step list of the workout
    ///   - fromIndex: index of the segment currently being executed
    ///   - elapsedInCurrentStep: seconds already elapsed in steps[fromIndex]
    static func scheduleAll(
        steps: [CyclingExecStep],
        fromIndex: Int,
        elapsedInCurrentStep: Int
    ) {
        cancelAll()

        var cumulative: TimeInterval = 0
        for i in fromIndex..<steps.count {
            let step = steps[i]
            let already = (i == fromIndex) ? elapsedInCurrentStep : 0
            let remaining = max(0, step.durationSeconds - already)
            cumulative += TimeInterval(remaining)

            let nextStep = (i + 1) < steps.count ? steps[i + 1] : nil

            let title: String
            let body: String
            if let next = nextStep {
                title = "\(step.name) done"
                body  = "Next: \(next.name) -- \(formatDuration(next.durationSeconds))"
            } else {
                title = "Workout complete"
                body  = "Cooldown finished -- tap to save"
            }

            scheduleOne(
                identifier: "\(prefix)\(i)",
                fireIn: cumulative,
                title: title,
                body: body
            )
        }
    }

    /// Cancels all pending cycling segment notifications.
    /// Idempotent and safe to call when none are scheduled.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Helpers

    private static func scheduleOne(
        identifier: String,
        fireIn: TimeInterval,
        title: String,
        body: String
    ) {
        // UNTimeIntervalNotificationTrigger requires a strictly positive interval.
        let interval = max(1, fireIn)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let m = seconds / 60
            let s = seconds % 60
            return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
        }
        return "\(seconds)s"
    }
}
