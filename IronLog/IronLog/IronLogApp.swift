import SwiftUI
import SwiftData

@main
struct IronLogApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SDPlan.self,
            SDTemplate.self,
            SDExerciseGroup.self,
            SDExercise.self,
            SDPrescribedSet.self,
            SDWorkout.self,
            SDExerciseLog.self,
            SDSetLog.self,
            // Cycling
            SDCyclingPlan.self,
            SDCyclingTemplate.self,
            SDCyclingSegment.self,
            SDCyclingWorkout.self,
            SDCyclingSegmentLog.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema migration failed -- typically a non-additive change like
            // a stored property type swap (e.g. weightKg Int -> Double).
            // Wipe the local SwiftData store and retry. Plans re-sync from
            // the server on next launch; workout history is lost on device
            // but preserved server-side (can be restored later).
            Self.wipeLocalStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after wipe: \(error)")
            }
        }
    }()

    /// Removes the SwiftData store files from Application Support so the next
    /// container init starts clean. Intentionally best-effort: the store URL
    /// is stable for the default ModelConfiguration on iOS 17+.
    private static func wipeLocalStore() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }
    }

    init() {
        // Install crash handlers as early as possible so we catch issues
        // happening during the rest of init / first frame.
        CrashReporter.install()

        UserDefaults.standard.register(defaults: [
            "syncServerURL": SyncService.defaultServerURL,
        ])
        RestTimerService.requestPermission()
        HealthKitManager.shared.requestAuthorization()

        // Ship any crash reports that were saved during a previous session.
        // Fire-and-forget: if the user is not authenticated or the network
        // fails, files stay on disk and we retry next launch.
        Task.detached(priority: .background) {
            await CrashReporter.uploadPending()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
