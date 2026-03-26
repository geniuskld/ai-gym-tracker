import SwiftUI

struct SlideButton: View {
    let onSlideRight: () -> Void
    let onSlideLeft: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false

    private let thumbSize: CGFloat = 64
    private let trackHeight: CGFloat = 72
    private let triggerThreshold: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - 16
            let minOffset = -(geo.size.width - thumbSize - 16)

            ZStack {
                // Track background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        HStack {
                            // Left hint
                            Label("Weight", systemImage: "scalemass")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .opacity(offset < -30 ? 1 : 0.3)
                                .padding(.leading, 20)

                            Spacer()

                            // Right hint
                            Label("Done", systemImage: "checkmark")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                                .opacity(offset > 30 ? 1 : 0.3)
                                .padding(.trailing, 20)
                        }
                    }

                // Thumb
                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 4)
                    .overlay {
                        Image(systemName: thumbIcon)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let clamped = min(
                                    max(value.translation.width, minOffset),
                                    maxOffset
                                )
                                offset = clamped
                            }
                            .onEnded { _ in
                                isDragging = false
                                if offset > triggerThreshold {
                                    // Slide right = done
                                    withAnimation(.spring(duration: 0.3)) {
                                        offset = 0
                                    }
                                    onSlideRight()
                                } else if offset < -triggerThreshold {
                                    // Slide left = weight entry
                                    withAnimation(.spring(duration: 0.3)) {
                                        offset = 0
                                    }
                                    onSlideLeft()
                                } else {
                                    withAnimation(.spring(duration: 0.3)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: trackHeight)
    }

    private var thumbColor: Color {
        if offset > triggerThreshold {
            return .green
        } else if offset < -triggerThreshold {
            return .orange
        }
        return .blue
    }

    private var thumbIcon: String {
        if offset > triggerThreshold {
            return "checkmark"
        } else if offset < -triggerThreshold {
            return "scalemass"
        }
        return "stop.fill"
    }
}
