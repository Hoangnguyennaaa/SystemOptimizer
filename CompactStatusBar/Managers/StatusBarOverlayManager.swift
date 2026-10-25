import UIKit
import SwiftUI

final class CompactOverlayPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }

        // 1. Nếu mở màn hình Cài đặt đầy đủ, nhận toàn bộ cảm ứng
        if self.rootViewController?.presentedViewController != nil {
            return hitView
        }

        // 2. Chỉ bắt chạm nếu chạm trúng Widget hoặc Popup HUD
        if hitView !== self && hitView !== self.rootViewController?.view {
            return hitView
        }

        // 3. Toàn bộ vùng trống trả về nil để chạm xuyên thấu xuống app bên dưới & SpringBoard
        return nil
    }
}

// View quản lý hiển thị trên toàn màn hình
struct OverlayRootView: View {
    @ObservedObject private var manager = SystemStatusManager.shared
    @State private var isHUDPresented: Bool = false
    @State private var isSettingsSheetPresented: Bool = false

    var body: some View {
        ZStack(alignment: alignmentForPosition(manager.position)) {
            if manager.isOverlayActive {
                VStack(spacing: 6) {
                    CombinedStatusGaugeView(isHUDPresented: $isHUDPresented)
                        .padding(.top, topPaddingForPosition(manager.position))
                        .padding(.horizontal, horizontalPaddingForPosition(manager.position))

                    if isHUDPresented {
                        StatusHUDPopupView(isPresented: $isHUDPresented) {
                            isSettingsSheetPresented = true
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
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
        case .coverStock, .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .center: return .top
        }
    }

    private func horizontalPaddingForPosition(_ pos: StatusPosition) -> CGFloat {
        switch pos {
        case .coverStock: return 4.0      // Đè khít chính xác lên vị trí icon Pin gốc của iPhone 7 Plus
        case .topRight: return 12.0
        case .topLeft: return 12.0
        case .center: return 0.0
        }
    }

    private func topPaddingForPosition(_ pos: StatusPosition) -> CGFloat {
        switch pos {
        case .coverStock: return 0.0      // Sát mép trên để che hoàn toàn icon pin gốc
        default: return 2.0
        }
    }
}

public final class StatusBarOverlayManager: ObservableObject {
    public static let shared = StatusBarOverlayManager()

    private var overlayWindow: CompactOverlayPassThroughWindow?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    public func startOverlay() {
        guard overlayWindow == nil else {
            overlayWindow?.isHidden = !SystemStatusManager.shared.isOverlayActive
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let screenBounds = UIScreen.main.bounds
            let window = CompactOverlayPassThroughWindow(frame: screenBounds)

            // Mức ưu tiên cực cao đè lên StatusBar của hệ thống
            window.windowLevel = UIWindow.Level(rawValue: 1000200.0)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.isHidden = !SystemStatusManager.shared.isOverlayActive

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
