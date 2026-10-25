import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var manager = SystemStatusManager.shared
    @State private var dummyHUD: Bool = false
    @State private var showRespringAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                // MARK: - Mục 1: Công tắc kích hoạt dịch vụ chính
                Section(header: Text("Trạng thái dịch vụ")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kích hoạt CompactStatusBar")
                                .font(.headline)
                            Text(manager.isOverlayActive ? "Đang chạy đè lên StatusBar" : "Dịch vụ đang tắt")
                                .font(.caption)
                                .foregroundColor(manager.isOverlayActive ? .green : .secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.isOverlayActive)
                            .labelsHidden()
                            .onChange(of: manager.isOverlayActive) { active in
                                if active {
                                    StatusBarOverlayManager.shared.startOverlay()
                                }
                            }
                    }

                    if manager.isOverlayActive {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Tiến trình ngầm (Keep-Alive): Hoạt động")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Mục 2: Xem trước trực tiếp
                Section(header: Text("Xem trước trực tiếp")) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            CombinedStatusGaugeView(isHUDPresented: $dummyHUD)
                            Text("Chạm đúp đổi Pin/RAM | Chạm 1 lần mở HUD | Nhấn giữ khóa máy")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Mục 3: Vị trí hiển thị (Có chế độ Đè che Pin gốc)
                Section(header: Text("Chế độ hiển thị & Vị trí")) {
                    Picker("Vị trí", selection: $manager.position) {
                        ForEach(StatusPosition.allCases) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    .onChange(of: manager.position) { _ in
                        manager.saveSettings()
                    }

                    if manager.position == .coverStock {
                        Text("💡 Chế độ 'Đè che Pin gốc': Widget được căn chỉnh tọa độ chính xác để nền đen che kín hoàn toàn biểu tượng pin mặc định của iOS 15 trên iPhone 7 Plus.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // MARK: - Mục 4: Kích thước & Độ trong suốt
                Section(header: Text("Kích thước & Độ trong suốt")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Độ to nhỏ (Scale)")
                            Spacer()
                            Text(String(format: "%.0f%%", manager.scale * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $manager.scale, in: 0.8...1.5, step: 0.05) { _ in
                            manager.saveSettings()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Độ mờ đục (Opacity)")
                            Spacer()
                            Text(String(format: "%.0f%%", manager.opacity * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $manager.opacity, in: 0.4...1.0, step: 0.05) { _ in
                            manager.saveSettings()
                        }
                    }
                }

                // MARK: - Mục 5: Tính năng bổ trợ
                Section(header: Text("Tính năng nâng cao")) {
                    Toggle("Tự động hiện tốc độ mạng khi > 100 KB/s", isOn: $manager.autoSpeedSwitch)
                        .onChange(of: manager.autoSpeedSwitch) { _ in manager.saveSettings() }

                    Toggle("Hiệu ứng phát sáng thở khi cắm sạc", isOn: $manager.enableBreathingGlow)
                        .onChange(of: manager.enableBreathingGlow) { _ in manager.saveSettings() }
                }

                // MARK: - Mục 6: Thao tác hệ thống
                Section(header: Text("Thao tác hệ thống")) {
                    Button {
                        showRespringAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.blue)
                            Text("Khởi động lại SpringBoard (Respring)")
                                .foregroundColor(.primary)
                        }
                    }

                    Button(role: .destructive) {
                        manager.position = .coverStock
                        manager.scale = 1.0
                        manager.opacity = 1.0
                        manager.autoSpeedSwitch = true
                        manager.enableBreathingGlow = true
                        manager.isOverlayActive = true
                        manager.saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Khôi phục cài đặt mặc định")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("CompactStatusBar")
            .alert("Khởi động lại SpringBoard", isPresented: $showRespringAlert) {
                Button("Hủy", role: .cancel) {}
                Button("Xác nhận Respring", role: .destructive) {
                    manager.respring()
                }
            } message: {
                Text("Làm mới giao diện SpringBoard để áp dụng các thay đổi hệ thống.")
            }
        }
    }
}
