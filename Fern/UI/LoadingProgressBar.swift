import SwiftUI

/// Barra fina de progresso no topo da página.
struct LoadingProgressBar: View {
    let progress: Double
    let isLoading: Bool

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * max(progress, 0.05))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .opacity(isLoading ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
        .accessibilityHidden(!isLoading)
    }
}
