import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PlansListView()
                .tabItem {
                    Label("Plans", systemImage: "list.bullet.clipboard")
                }

            Text("Workout")
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            Text("History")
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}
