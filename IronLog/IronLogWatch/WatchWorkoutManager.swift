import Foundation
import HealthKit
import WatchConnectivity

// Manages HKWorkoutSession on Apple Watch.
// Starts/stops in response to WatchConnectivity messages from iPhone.
// Collects heart rate, calories via HKLiveWorkoutBuilder.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {

    static let shared = WatchWorkoutManager()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isActive: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var isCardioMode: Bool = false

    private var startDate: Date?
    private var timer: Timer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        wc.delegate = self
        wc.activate()
    }

    func requestAuthorization() {
        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: types
        ) { _, _ in }
    }

    func startWorkout(activity: String = "strength") async {
        guard session == nil else { return }

        let config = HKWorkoutConfiguration()
        switch activity {
        case "cycling":
            config.activityType = .cycling
            isCardioMode = true
        default:
            config.activityType = .traditionalStrengthTraining
            isCardioMode = false
        }
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: config
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: .now)
            try await builder.beginCollection(at: .now)

            startDate = .now
            isActive = true
            startTimer()
        } catch {
            // session setup failed
        }
    }

    func endWorkout() {
        session?.end()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = Int(Date.now.timeIntervalSince(start))
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func saveAndReset() async {
        stopTimer()
        guard let builder else { return }
        do {
            try await builder.endCollection(at: .now)
            try await builder.finishWorkout()
        } catch {
            // save failed
        }
        session = nil
        self.builder = nil
        heartRate = 0
        activeCalories = 0
        elapsedSeconds = 0
        isCardioMode = false
    }

    /// Forwards a HR sample to the iPhone via WatchConnectivity. Only
    /// invoked when the current activity is cardio. Best-effort: drops
    /// the sample silently if the iPhone is not reachable.
    private func sendHRToiPhone(_ bpm: Int) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(
            [
                "event": "hr_sample",
                "bpm": bpm,
                "t": Date().timeIntervalSince1970,
            ],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - WCSessionDelegate

extension WatchWorkoutManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = message["command"] as? String else {
            replyHandler(["status": "unknown"])
            return
        }
        let activity = message["activity"] as? String ?? "strength"
        Task { @MainActor in
            switch command {
            case "startWorkout":
                await startWorkout(activity: activity)
                replyHandler(["status": "started"])
            case "stopWorkout":
                endWorkout()
                replyHandler(["status": "stopped"])
            default:
                replyHandler(["status": "unknown"])
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .ended, .stopped:
                isActive = false
                await saveAndReset()
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            isActive = false
            stopTimer()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let qType = type as? HKQuantityType,
                      let stats = workoutBuilder.statistics(for: qType)
                else { continue }

                switch qType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    let bpm = stats.mostRecentQuantity()?
                        .doubleValue(for: unit) ?? 0
                    heartRate = bpm
                    if isCardioMode, bpm > 0 {
                        sendHRToiPhone(Int(bpm.rounded()))
                    }

                case HKQuantityType(.activeEnergyBurned):
                    activeCalories = stats.sumQuantity()?
                        .doubleValue(for: .kilocalorie()) ?? 0

                default:
                    break
                }
            }
        }
    }
}
