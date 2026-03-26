import SwiftUI

struct SlideButton: View {
    let leftLabel: String
    let leftIcon: String
    let rightLabel: String
    let rightIcon: String
    let onSlideRight: () -> Void
    let onSlideLeft: () -> Void

    @State private var offset: CGFloat = 0

    private let thumbSize: CGFloat = 64
    private let trackHeight: CGFloat = 72
    private let triggerThreshold: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            let maxOff = geo.size.width - thumbSize - 16

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        HStack {
                            Label(leftLabel, systemImage: leftIcon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .opacity(offset < -30 ? 1 : 0.3)
                                .padding(.leading, 20)

                            Spacer()

                            Label(rightLabel, systemImage: rightIcon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                                .opacity(offset > 30 ? 1 : 0.3)
                                .padding(.trailing, 20)
                        }
                    }

                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 4)
                    .overlay {
                        Image(systemName: thumbIconName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = min(max(value.translation.width, -maxOff), maxOff)
                            }
                            .onEnded { _ in
                                if offset > triggerThreshold {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                    onSlideRight()
                                } else if offset < -triggerThreshold {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                    onSlideLeft()
                                } else {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: trackHeight)
    }

    private var thumbColor: Color {
        if offset > triggerThreshold { return .green }
        if offset < -triggerThreshold { return .orange }
        return .blue
    }

    private var thumbIconName: String {
        if offset > triggerThreshold { return rightIcon }
        if offset < -triggerThreshold { return leftIcon }
        return "circle.fill"
    }
}
