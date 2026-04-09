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
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        UserDefaults.standard.register(defaults: [
            "syncServerURL": SyncService.defaultServerURL,
        ])
        RestTimerService.requestPermission()
        HealthKitManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
