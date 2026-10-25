import SwiftUI

public struct IslandCapsuleView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var isExpanded: Bool = false
    @State private var showSettingsModal: Bool = false

    public init() {}

    public var body: some View {
        VStack {
            capsuleContent
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showSettingsModal) {
            SettingsView()
        }
    }

    // MARK: - Capsule Base Container
    private var capsuleContent: some View {
        ZStack {
            // Background với viền nhám và blur
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 14, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 24 : 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4)

            if isExpanded {
                expandedView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                collapsedView
                    .transition(.opacity)
            }
        }
        .frame(
            width: isExpanded ? 380 : 220,
            height: isExpanded ? 76 : 28
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                isExpanded.toggle()
            }
        }
        .onLongPressGesture {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showSettingsModal = true
        }
    }

    // MARK: - Collapsed View
    private var collapsedView: some View {
        HStack(spacing: 8) {
            // 1. Pin
            HStack(spacing: 3) {
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
                Text("\(monitor.batteryLevel)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(batteryTextColor)
            }

            Divider()
                .frame(height: 12)
                .background(Color.white.opacity(0.3))

            // 2. Mạng & Tốc độ
            HStack(spacing: 3) {
                Image(systemName: monitor.networkType == .wifi ? "wifi" : (monitor.networkType == .cellular ? "antenna.radiowaves.left.and.right" : "wifi.slash"))
                    .font(.system(size: 10))
                    .foregroundColor(monitor.networkType == .none ? .red : .blue)
                Text(monitor.downloadSpeedString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 12)
                .background(Color.white.opacity(0.3))

            // 3. RAM Free (A10 Fusion)
            HStack(spacing: 2) {
                Text("RAM")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                Text(String(format: "%.1fG", monitor.ramUsage.freeGB))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(monitor.ramUsage.freeGB < 0.5 ? .red : .green)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Expanded View
    private var expandedView: some View {
        HStack(spacing: 12) {
            // Cột 1: Thông số Pin chi tiết
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100")
                        .foregroundColor(batteryTextColor)
                    Text("\(monitor.batteryLevel)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                // Thanh đo pin thu nhỏ
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 5)
                        Capsule()
                            .fill(batteryTextColor)
                            .frame(width: geo.size.width * CGFloat(monitor.batteryLevel) / 100.0, height: 5)
                    }
                }
                .frame(height: 5)

                Text(monitor.isCharging ? "Đang sạc" : "Dùng pin")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 48)
                .background(Color.white.opacity(0.2))

            // Cột 2: Mạng & Lưu lượng DL/UL
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: monitor.networkType == .wifi ? "wifi" : "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                    Text(monitor.networkType.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                        .foregroundColor(.green)
                    Text(monitor.downloadSpeedString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text(monitor.uploadSpeedString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 48)
                .background(Color.white.opacity(0.2))

            // Cột 3: Bộ nhớ RAM A10 Fusion (3GB)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .foregroundColor(.purple)
                    Text("A10 RAM")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(String(format: "Trống: %.2f GB", monitor.ramUsage.freeGB))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(monitor.ramUsage.freeGB < 0.6 ? .orange : .green)

                Text("Tổng: 3.0 GB")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
    }

    private var batteryTextColor: Color {
        if monitor.isCharging {
            return .green
        } else if monitor.batteryLevel <= 20 {
            return .red
        } else if monitor.batteryLevel <= 40 {
            return .yellow
        } else {
            return .white
        }
    }
}
