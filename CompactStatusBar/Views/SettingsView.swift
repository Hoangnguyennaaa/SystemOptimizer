import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var manager = SystemStatusManager.shared
    @State private var dummyHUD: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Xem trước trực tiếp")) {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            CombinedStatusGaugeView(isHUDPresented: $dummyHUD)
                            Text("Chạm đúp đổi Pin/RAM | Chạm 1 lần mở HUD")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }

                Section(header: Text("Vị trí hiển thị trên StatusBar")) {
                    Picker("Vị trí", selection: $manager.position) {
                        ForEach(StatusPosition.allCases) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: manager.position) { _ in
                        manager.saveSettings()
                    }
                }

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

                Section(header: Text("Tính năng nâng cao")) {
                    Toggle("Tự động hiện tốc độ tải khi > 100 KB/s", isOn: $manager.autoSpeedSwitch)
                        .onChange(of: manager.autoSpeedSwitch) { _ in manager.saveSettings() }

                    Toggle("Hiệu ứng phát sáng thở khi cắm sạc (Breathing Glow)", isOn: $manager.enableBreathingGlow)
                        .onChange(of: manager.enableBreathingGlow) { _ in manager.saveSettings() }
                }

                Section(header: Text("Cử chỉ tương tác trên Widget")) {
                    Text("• Chạm 1 lần: Mở bảng tóm tắt phần cứng (HUD).")
                    Text("• Chạm 2 lần: Hoán đổi vòng ngoài giữa đo Pin % và RAM %.")
                    Text("• Nhấn giữ: Khóa máy ngay lập tức.")
                }

                Section {
                    Button(role: .destructive) {
                        manager.position = .topRight
                        manager.scale = 1.0
                        manager.opacity = 0.95
                        manager.autoSpeedSwitch = true
                        manager.enableBreathingGlow = true
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
        }
    }
}
