import SwiftUI

@main
struct IronLogWatchApp: App {

    var body: some Scene {
        WindowGroup {
            LiveWorkoutView()
                .environmentObject(WatchWorkoutManager.shared)
                .onAppear {
                    WatchWorkoutManager.shared.requestAuthorization()
                }
        }
    }
}
