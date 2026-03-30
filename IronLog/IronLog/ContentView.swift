import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var plans: [SDPlan]
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt == nil }
    ) private var activeWorkouts: [SDWorkout]

    @State private var selectedTab: Tab = .workout

    enum Tab: Hashable {
        case plans, workout, history
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PlansListView()
                .tabItem {
                    Label("Plans", systemImage: "list.bullet.clipboard")
                }
                .tag(Tab.plans)

            TemplatePicker(autoResumeWorkout: !activeWorkouts.isEmpty)
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(Tab.workout)

            WorkoutHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.history)
        }
        .onAppear {
            if !plans.isEmpty {
                selectedTab = .workout
            }
        }
    }
}
