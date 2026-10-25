import UIKit
import SwiftUI

final class CompactOverlayPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }

        // 1. Nếu đang mở màn hình Cài đặt đầy đủ, nhận toàn bộ cảm ứng
        if self.rootViewController?.presentedViewController != nil {
            return hitView
        }

        // 2. Nếu chạm trúng các thành phần con tương tác (Gauge hoặc Popup HUD)
        // chứ không phải là view nền trong suốt
        if hitView !== self && hitView !== self.rootViewController?.view {
            return hitView
        }

        // 3. Toàn bộ vùng trống khác trả về nil để chạm xuyên thấu xuống hệ thống
        return nil
    }
}

// View chứa Overlay Widget và Popup HUD trên StatusBar
struct OverlayRootView: View {
    @ObservedObject private var manager = SystemStatusManager.shared
    @State private var isHUDPresented: Bool = false
    @State private var isSettingsSheetPresented: Bool = false

    var body: some View {
        ZStack(alignment: alignmentForPosition(manager.position)) {
            // Widget Gauge Icon
            VStack(spacing: 8) {
                CombinedStatusGaugeView(isHUDPresented: $isHUDPresented)
                    .padding(.top, 2)
                    .padding(.horizontal, horizontalPaddingForPosition(manager.position))

                if isHUDPresented {
                    StatusHUDPopupView(isPresented: $isHUDPresented) {
                        isSettingsSheetPresented = true
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignmentForPosition(manager.position))
        .sheet(isPresented: $isSettingsSheetPresented) {
            SettingsView()
        }
    }

    private func alignmentForPosition(_ pos: StatusPosition) -> Alignment {
        switch pos {
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .center: return .top
        }
    }

    private func horizontalPaddingForPosition(_ pos: StatusPosition) -> CGFloat {
        switch pos {
        case .topRight: return 12.0
        case .topLeft: return 12.0
        case .center: return 0.0
        }
    }
}

public final class StatusBarOverlayManager: ObservableObject {
    public static let shared = StatusBarOverlayManager()

    private var overlayWindow: CompactOverlayPassThroughWindow?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    public func startOverlay() {
        guard overlayWindow == nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let screenBounds = UIScreen.main.bounds
            let window = CompactOverlayPassThroughWindow(frame: screenBounds)

            // Mức ưu tiên cao hơn StatusBar chuẩn + 200
            window.windowLevel = UIWindow.Level(rawValue: 1000200.0)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isHidden = false

            let rootView = OverlayRootView()
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false

            window.rootViewController = hostingController
            window.makeKeyAndVisible()

            self.overlayWindow = window
            self.maintainBackgroundAssertion()
        }
    }

    private func maintainBackgroundAssertion() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "CompactStatusBarKeepAlive") { [weak self] in
            self?.maintainBackgroundAssertion()
        }
    }
}
