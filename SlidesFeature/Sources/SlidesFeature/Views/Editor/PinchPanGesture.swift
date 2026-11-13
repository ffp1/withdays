import SwiftUI
import UIKit

/// Two fingers: how far they've spread (scale) and where their middle is, so a pinch can also move what it zooms.
/// SwiftUI's own pinch doesn't report where the fingers are now.
struct PinchPanGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case began, changed, ended
    }

    /// The phase, the scale since the fingers went down, and their middle in the view's own space.
    var onChange: (Phase, CGFloat, CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        switch recognizer.state {
        case .began: onChange(.began, recognizer.scale, location)
        case .changed: onChange(.changed, recognizer.scale, location)
        case .ended, .cancelled, .failed: onChange(.ended, recognizer.scale, location)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
