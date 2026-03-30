import SwiftUI

#if DEBUG
struct DebugLogView: View {
    let vm: ActiveWorkoutViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(jsonString)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Workout Log JSON")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var jsonString: String {
        guard let workout = vm.workout else {
            return "{ \"error\": \"no active workout\" }"
        }
        return WorkoutExportService.exportJSON(workout)
    }
}
#endif
