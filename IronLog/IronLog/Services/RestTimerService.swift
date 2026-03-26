import Foundation
import Combine
import UIKit

@MainActor
@Observable
final class RestTimerService {
    var secondsRemaining: Int = 0
    var totalSeconds: Int = 0
    var isRunning: Bool = false

    private var timerCancellable: AnyCancellable?

    func start(seconds: Int) {
        stop()
        totalSeconds = seconds
        secondsRemaining = seconds
        isRunning = true

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.secondsRemaining > 0 {
                    self.secondsRemaining -= 1
                } else {
                    self.timerFinished()
                }
            }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
    }

    func skip() {
        stop()
        secondsRemaining = 0
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - secondsRemaining) / Double(totalSeconds)
    }

    var formattedTime: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func timerFinished() {
        stop()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Stopwatch (counts up, for set duration)

@MainActor
@Observable
final class StopwatchService {
    var elapsedSeconds: Int = 0
    var isRunning: Bool = false

    private var timerCancellable: AnyCancellable?
    private var startDate: Date?

    func start() {
        stop()
        elapsedSeconds = 0
        isRunning = true
        startDate = .now

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = Int(Date.now.timeIntervalSince(start))
            }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
    }

    var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
