import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var plans: [SDPlan]
    @Query(
        filter: #Predicate<SDWorkout> { $0.finishedAt == nil }
    ) private var activeWorkouts: [SDWorkout]
    @Environment(\.modelContext) private var context

    @State private var selectedTab: Tab = .workout

    enum Tab: Hashable {
        case plans, workout, history, settings
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

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
        .onAppear {
            if !plans.isEmpty {
                selectedTab = .workout
            }
        }
        .task {
            await PlanSyncHelper.syncIfNeeded(context: context)
        }
    }
}
