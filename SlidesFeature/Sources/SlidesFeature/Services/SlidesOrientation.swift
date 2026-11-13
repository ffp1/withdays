import UIKit

/// Which way the app may turn. The host's app delegate returns this from
/// `application(_:supportedInterfaceOrientationsFor:)`; the player turns it to landscape while it plays.
public enum SlidesOrientation {
    @MainActor public static var supported: UIInterfaceOrientationMask = .portrait

    /// Allows only `mask` and turns the screen to `orientation`.
    @MainActor
    static func lock(_ mask: UIInterfaceOrientationMask, turnTo orientation: UIInterfaceOrientationMask) {
        supported = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }
}

/// A slide copied with コピー, to paste in this deck or another (in the app only).
@MainActor
enum SlideClipboard {
    static var slide: SlideContent?
    /// The deck its images are in.
    static var deck: UUID?
}
