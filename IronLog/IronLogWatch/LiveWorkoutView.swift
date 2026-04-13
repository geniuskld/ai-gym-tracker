import SwiftUI

struct LiveWorkoutView: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    var body: some View {
        if manager.isActive {
            activeView
        } else {
            idleView
        }
    }

    private var activeView: some View {
        VStack(spacing: 12) {
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("\(Int(manager.heartRate))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                Text("bpm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Timer
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
                Text(formattedTime)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }

            // Calories
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(Int(manager.activeCalories))")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("IronLog")
                .font(.headline)
            Text("Start workout\non iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var formattedTime: String {
        let m = manager.elapsedSeconds / 60
        let s = manager.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
