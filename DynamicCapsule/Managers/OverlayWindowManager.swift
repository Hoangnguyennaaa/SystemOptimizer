import UIKit
import SwiftUI

final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }

        // 1. Nếu có màn hình Cài đặt (Modal Sheet) đang mở, nhận toàn bộ tương tác
        if self.rootViewController?.presentedViewController != nil {
            return hitView
        }

        // 2. Vùng nhận chạm của Capsule ở sát mép trên màn hình (y: 0 đến 90 pt)
        // iPhone 7 Plus có chiều rộng 414 pt. Capsule nằm trong khoảng này.
        if point.y <= 90.0 {
            // Nếu không phải là root view rỗng thì trả về view được chạm
            return hitView
        }

        // 3. Toàn bộ khu vực bên dưới cho phép chạm xuyên thấu (Pass-through)
        // để người dùng vuốt, chạm ứng dụng bên dưới hoặc SpringBoard bình thường
        return nil
    }
}

public final class OverlayWindowManager: ObservableObject {
    public static let shared = OverlayWindowManager()

    private var overlayWindow: PassThroughWindow?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    public func startOverlay() {
        guard overlayWindow == nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let screenBounds = UIScreen.main.bounds
            let window = PassThroughWindow(frame: screenBounds)

            // Đặt mức ưu tiên cao hơn StatusBar và Alert hệ thống
            window.windowLevel = UIWindow.Level(rawValue: 1000100.0)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isHidden = false

            // Khởi tạo SwiftUI Hosting Controller
            let capsuleView = IslandCapsuleView()
            let hostingController = UIHostingController(rootView: capsuleView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false

            window.rootViewController = hostingController
            window.makeKeyAndVisible()

            self.overlayWindow = window
            self.maintainBackgroundAssertion()
        }
    }

    // Duy trì tiến trình chạy nền không bị Watchdog / iOS 15 suspend
    private func maintainBackgroundAssertion() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "DynamicCapsuleKeepAlive") { [weak self] in
            self?.maintainBackgroundAssertion()
        }
    }
}
