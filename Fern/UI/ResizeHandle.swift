import AppKit
import SwiftUI

/// Alça invisível para redimensionar arrastando (barra lateral, painel do inspetor).
/// Mostra o cursor de redimensionar e volta ao tamanho padrão com clique duplo.
struct ResizeHandle: View {
    let axis: Axis
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// `true` quando arrastar para cima/esquerda deve aumentar (alça no topo do painel).
    var grows: Bool = true
    var thickness: CGFloat = 10
    /// Chamado ao arrastar bem abaixo do mínimo (ex.: esconder a barra lateral).
    var collapse: (() -> Void)?

    @State private var dragStart: Double?
    @State private var isHovering = false

    var body: some View {
        Color.clear
            .frame(width: axis == .horizontal ? thickness : nil, height: axis == .vertical ? thickness : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != isHovering else { return }
                isHovering = inside
                if inside {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let delta = axis == .horizontal ? drag.translation.width : drag.translation.height
                        let proposed = start + (grows ? delta : -delta)
                        if let collapse, proposed < range.lowerBound - 80 {
                            dragStart = nil
                            collapse()
                            return
                        }
                        value = min(max(proposed, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { value = defaultValue }
            .accessibilityElement()
            .accessibilityLabel(axis == .horizontal ? "Resize Sidebar" : "Resize Panel")
            .accessibilityValue(Text(Int(value), format: .number))
            .accessibilityAdjustableAction { direction in
                let step = 20.0
                switch direction {
                case .increment: value = min(value + step, range.upperBound)
                case .decrement: value = max(value - step, range.lowerBound)
                @unknown default: break
                }
            }
    }
}
