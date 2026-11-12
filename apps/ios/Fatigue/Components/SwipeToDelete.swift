import SwiftUI
import UIKit

/// Slide a row left to reveal a trash button behind it. Tap the button, or keep sliding past
/// half the row, to delete.
///
/// The row follows the finger 1:1 and settles with a spring that starts at the finger's speed,
/// so a flick opens or closes it without a visible seam. Dragging right past the resting point
/// gets harder the further you go instead of stopping dead.
struct SwipeToDelete<Content: View>: View {
    @Environment(\.palette) private var palette
    let accessibilityName: String
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var isDeleting = false

    /// How far the row rests when open: enough for one comfortable trash button.
    private var revealWidth: CGFloat { Tokens.Size.control + Tokens.Space.xxl }
    private var isOpen: Bool { offset < 0 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: delete) {
                Image(systemName: "trash")
                    .foregroundStyle(palette.background)
                    .frame(width: max(revealWidth, -offset), alignment: .center)
                    .frame(maxHeight: .infinity)
                    .background(palette.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isOpen ? 1 : 0)
            .accessibilityHidden(true)

            content
                .background(palette.background)
                .offset(x: offset)
                .overlay {
                    // While open, a tap on the row closes it instead of reaching the cells underneath.
                    if isOpen, !isDeleting {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { settle(to: 0, velocity: 0) }
                    }
                }
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(HorizontalPan(onChange: track, onEnd: release))
        .sensoryFeedback(.impact(weight: .light), trigger: pastDeletePoint) { _, past in past }
        .accessibilityAction(named: "Delete \(accessibilityName)", onDelete)
    }

    private var pastDeletePoint: Bool { width > 0 && -offset > width / 2 }

    private func track(_ translation: CGFloat) {
        let raw = dragStart + translation
        offset = raw > 0 ? Self.rubberBand(raw, dimension: width) : raw
    }

    private func release(_ translation: CGFloat, _ velocity: CGFloat) {
        // Aim for where the flick would carry the row, not where the finger let go.
        let projected = offset + Self.project(velocity)
        if pastDeletePoint || (width > 0 && -projected > width * 0.75) {
            delete()
        } else if -projected > revealWidth / 2 {
            settle(to: -revealWidth, velocity: velocity)
        } else {
            settle(to: 0, velocity: velocity)
        }
    }

    private func settle(to target: CGFloat, velocity: CGFloat) {
        let distance = target - offset
        let relative = distance == 0 ? 0 : velocity / distance
        withAnimation(.interpolatingSpring(duration: Tokens.Motion.standard, bounce: 0, initialVelocity: relative)) {
            offset = target
        }
        dragStart = target
    }

    private func delete() {
        isDeleting = true
        withAnimation(.standard) { offset = -width }
        Task {
            try? await Task.sleep(for: .seconds(Tokens.Motion.quick))
            withAnimation(.standard) { onDelete() }
        }
    }

    /// Where a flick at this speed would come to rest, using the scroll deceleration curve.
    private static func project(_ velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Resistance past the edge: the further you drag, the less the row follows.
    private static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }
}

/// A pan that only starts when the finger moves more sideways than up or down,
/// so vertical scrolling through the workout is never caught by a row.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: onChange(translation)
        case .ended, .cancelled: onEnd(translation, pan.velocity(in: pan.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
