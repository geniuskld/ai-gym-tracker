import SwiftUI

struct RestTimerView: View {
    @Bindable var vm: ActiveWorkoutViewModel

    var body: some View {
        if vm.restTimer.isRunning {
            VStack(spacing: 8) {
                HStack {
                    Text("Rest")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Text(vm.restTimer.formattedTime)
                        .font(.title2.weight(.bold).monospacedDigit())

                    Spacer()

                    Button("Skip") {
                        vm.skipTimer()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                }

                ProgressView(value: vm.restTimer.progress)
                    .tint(.blue)
            }
            .padding()
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 4)
            .padding(.horizontal)
            .onChange(of: vm.restTimer.isRunning) { _, newValue in
                if !newValue {
                    vm.onTimerFinished()
                }
            }
        }
    }
}
