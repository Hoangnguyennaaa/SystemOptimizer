import SwiftUI

public struct StatusHUDPopupView: View {
    @ObservedObject private var manager = SystemStatusManager.shared
    @Binding public var isPresented: Bool
    public var onOpenSettings: () -> Void

    public init(isPresented: Binding<Bool>, onOpenSettings: @escaping () -> Void) {
        self._isPresented = isPresented
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.cyan)
                Text("CompactStatusBar HUD")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }

            Divider()

            // Dữ liệu giám sát
            VStack(spacing: 8) {
                // Pin
                HStack {
                    Label("\(Int(manager.batteryLevel * 100))%", systemImage: manager.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(manager.isCharging ? .green : .primary)
                    Spacer()
                    Text(manager.isCharging ? "Đang sạc" : (manager.isLowPowerMode ? "Nguồn điện thấp" : "Bình thường"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // RAM (A10 Fusion)
                HStack {
                    Label("RAM", systemImage: "memorychip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)
                    Spacer()
                    Text(String(format: "Trống: %.2f GB / %.1f GB", manager.ramFreeGB, manager.ramTotalGB))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }

                // Tốc độ mạng
                HStack {
                    Label(manager.isWifiConnected ? "Wi-Fi" : "Di động", systemImage: manager.isWifiConnected ? "wifi" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                    Spacer()
                    Text("Tải: \(manager.downloadSpeedFormatted)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                }

                // Nhiệt độ
                HStack {
                    Label("Nhiệt độ chip", systemImage: "thermometer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                    Spacer()
                    Text(manager.thermalStateDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Các nút thao tác nhanh
            HStack(spacing: 10) {
                Button {
                    manager.lockDevice()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Khóa máy")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(6)
                }

                Button {
                    isPresented = false
                    onOpenSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("Cài đặt")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
        )
    }
}
