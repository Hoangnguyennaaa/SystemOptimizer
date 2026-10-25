import SwiftUI

@main
struct DynamicCapsuleApp: App {
    init() {
        // Tự động kích hoạt Overlay Window khi ứng dụng khởi chạy
        OverlayWindowManager.shared.startOverlay()
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .onAppear {
                    OverlayWindowManager.shared.startOverlay()
                }
        }
    }
}
