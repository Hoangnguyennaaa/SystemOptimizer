import SwiftUI

// Hình học vòng cung khuyết ở đáy (quét 270 độ, chừa góc 90 độ ở đáy cho 5 chấm sóng)
struct GaugeArcShape: Shape {
    let startAngle: Angle = .degrees(135)
    let endAngle: Angle = .degrees(45)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

public struct CombinedStatusGaugeView: View {
    @ObservedObject private var manager = SystemStatusManager.shared

    // Chuyển đổi giữa đo Pin và đo RAM khi chạm 2 lần
    @State private var isShowingRAM: Bool = false
    @State private var isGlowBreathing: Bool = false
    @Binding public var isHUDPresented: Bool

    private let size: CGFloat = 38.0
    private let strokeWidth: CGFloat = 3.2

    public init(isHUDPresented: Binding<Bool>) {
        self._isHUDPresented = isHUDPresented
    }

    public var body: some View {
        ZStack {
            // Nền đen mờ tạo độ tương phản cao trên StatusBar
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)

            // 1. Vòng cung Pin / RAM (Outer Arc)
            outerGaugeArc

            // 2. Trung tâm: Wi-Fi Waves hoặc Tốc độ mạng DL (> 100 KB/s)
            centerNetworkIcon

            // 3. 5 Chấm sóng di động xếp theo đường cong đáy (5-Dot Cellular Arc)
            bottomCellularDots
        }
        .frame(width: size, height: size)
        .scaleEffect(manager.scale)
        .opacity(manager.opacity)
        .contentShape(Circle())
        .onTapGesture(count: 2) {
            // Chạm đúp: Đổi hiển thị Pin <-> RAM
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isShowingRAM.toggle()
            }
        }
        .onTapGesture(count: 1) {
            // Chạm 1 lần: Bật/tắt HUD tóm tắt trạng thái
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                isHUDPresented.toggle()
            }
        }
        .onLongPressGesture {
            // Nhấn giữ: Khóa màn hình tức thì
            manager.lockDevice()
        }
        .onAppear {
            if manager.enableBreathingGlow {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isGlowBreathing = true
                }
            }
        }
    }

    // MARK: - 1. Vòng cung Pin / RAM
    private var outerGaugeArc: some View {
        let progress = isShowingRAM ? manager.ramUsedPercent : manager.batteryLevel
        let activeColor = currentGaugeColor

        return ZStack {
            // Vòng ray nền
            GaugeArcShape()
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size - strokeWidth, height: size - strokeWidth)

            // Vòng tiến trình
            GaugeArcShape()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(activeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size - strokeWidth, height: size - strokeWidth)
                .shadow(
                    color: (manager.isCharging && manager.enableBreathingGlow)
                        ? activeColor.opacity(isGlowBreathing ? 0.95 : 0.3)
                        : Color.clear,
                    radius: (manager.isCharging && manager.enableBreathingGlow) ? (isGlowBreathing ? 5.5 : 2.0) : 0
                )
        }
    }

    private var currentGaugeColor: Color {
        if isShowingRAM {
            if manager.ramUsedPercent > 0.85 { return .red }
            if manager.ramUsedPercent > 0.65 { return .orange }
            return .cyan
        } else {
            if manager.isCharging { return .green }
            if manager.isLowPowerMode { return .yellow }
            if manager.batteryLevel <= 0.20 { return .red }
            return Color.white.opacity(0.88)
        }
    }

    // MARK: - 2. Tâm Wi-Fi hoặc Tốc độ mạng
    private var centerNetworkIcon: some View {
        Group {
            // Nếu lưu lượng > 100 KB/s và bật tự động chuyển sang tốc độ mạng
            if manager.autoSpeedSwitch && manager.downloadSpeedBytesPerSec > 100_000 {
                VStack(spacing: -1) {
                    Text(manager.downloadSpeedFormatted)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Text("DL")
                        .font(.system(size: 5.5, weight: .heavy))
                        .foregroundColor(.secondary)
                }
            } else if manager.isWifiConnected {
                // Vẽ 3 cung sóng Wi-Fi và chấm tròn tâm
                wifiWavesIcon
            } else if manager.isCellularConnected {
                Text("LTE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }

    private var wifiWavesIcon: some View {
        Canvas { context, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height * 0.72)
            let waveRadii: [CGFloat] = [2.2, 5.0, 7.8]

            // 3 vòng cung sóng Wi-Fi
            for r in waveRadii {
                var path = Path()
                path.addArc(center: center, radius: r, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                context.stroke(path, with: .color(.white.opacity(0.95)), lineWidth: 1.1)
            }

            // Chấm gốc tâm
            let dotRect = CGRect(x: center.x - 1.1, y: center.y - 1.1, width: 2.2, height: 2.2)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))
        }
        .frame(width: 18, height: 18)
    }

    // MARK: - 3. 5 Chấm sóng di động ở đáy
    private var bottomCellularDots: some View {
        let angles: [Double] = [58, 74, 90, 106, 122]
        let radius = (size / 2.0) - 2.2

        return ZStack {
            ForEach(0..<5) { index in
                let angleRad = angles[index] * .pi / 180.0
                let x = (size / 2.0) + radius * CGFloat(cos(angleRad))
                let y = (size / 2.0) + radius * CGFloat(sin(angleRad))
                let isLit = index < manager.cellularBars

                Circle()
                    .fill(isLit ? Color.white : Color.white.opacity(0.22))
                    .frame(width: 2.0, height: 2.0)
                    .position(x: x, y: y)
            }
        }
        .frame(width: size, height: size)
    }
}
