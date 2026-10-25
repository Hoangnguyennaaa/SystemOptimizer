# SystemOptimizer (iCleanerLite) for iOS 15 (iPhone 7 Plus)

Công cụ quản lý và tối ưu hóa Launch Daemons hệ thống trên iOS 15.0 - 15.8.x, hỗ trợ TrollStore và Jailbreak Rootless (Dopamine, Palera1n).

## Cấu trúc thư mục

- `RootHelper/main.c`: C binary chạy với quyền root (`setuid(0)`, `launchctl`, can thiệp `/var/jb/Library/LaunchDaemons`).
- `Entitlements/`: Chứa file `app.plist` và `roothelper.plist` cấp quyền `com.apple.private.security.no-sandbox` và `platform-application`.
- `SystemOptimizer/`: Mã nguồn SwiftUI (iOS 15).
  - `App/SystemOptimizerApp.swift`: Entry point.
  - `Models/DaemonItem.swift`: Định nghĩa model và phân cấp rủi ro (An toàn, Cân nhắc, Nguy hiểm).
  - `Services/DaemonManager.swift`: Giao tiếp với `RootHelper` qua `posix_spawn`.
  - `Views/ContentView.swift`: Giao diện danh sách toggle và nút khôi phục mặc định.
- `build.sh`: Script tự động compile, ký entitlements và đóng gói thành `SystemOptimizer.ipa`.
