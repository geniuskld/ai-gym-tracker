import SwiftUI

enum CockpitPalette {
    static let background = Color(red: 0.018, green: 0.020, blue: 0.024)
    static let panel = Color(red: 0.082, green: 0.094, blue: 0.110)
    static let panelElevated = Color(red: 0.105, green: 0.118, blue: 0.136)
    static let border = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.54)
    static let faint = Color.white.opacity(0.30)
    static let blue = Color(red: 0.22, green: 0.56, blue: 1.0)
    static let cyan = Color(red: 0.22, green: 0.78, blue: 0.95)
    static let green = Color(red: 0.35, green: 0.80, blue: 0.38)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let purple = Color(red: 0.62, green: 0.42, blue: 1.0)
    static let magenta = Color(red: 0.92, green: 0.36, blue: 0.88)
    static let red = Color(red: 1.0, green: 0.32, blue: 0.32)
}

struct CockpitPanel<Content: View>: View {
    private let spacing: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(
        spacing: CGFloat = 10,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CockpitPalette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CockpitPalette.border)
        }
    }
}

struct CockpitChip: View {
    let text: String
    var color: Color = CockpitPalette.muted
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.13), in: Capsule())
        .overlay {
            Capsule().strokeBorder(color.opacity(0.25))
        }
    }
}

struct CockpitMetric: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(CockpitPalette.faint)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CockpitPrimaryButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                tint.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}

struct CockpitIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(CockpitPalette.panelElevated, in: Circle())
                .overlay {
                    Circle().strokeBorder(CockpitPalette.border)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
