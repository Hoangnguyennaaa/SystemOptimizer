import SwiftUI

@main
struct CompactStatusBarApp: App {
    init() {
        // Tự động khởi động thanh StatusBar Overlay khi ứng dụng mở
        StatusBarOverlayManager.shared.startOverlay()
    }

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .onAppear {
                    StatusBarOverlayManager.shared.startOverlay()
                }
        }
    }
}
