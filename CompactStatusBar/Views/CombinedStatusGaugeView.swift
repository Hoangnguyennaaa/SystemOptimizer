import SwiftUI

// MARK: - Vòng cung hình học ngoài (Outer Gauge Arc Shape)
// Quét 270 độ theo chiều kim đồng hồ, chừa góc 90 độ ở đáy cho cụm chấm sóng di động
struct GaugeArcShape: Shape {
    let startAngle: Angle = .degrees(135)
    let endAngle: Angle = .degrees(45)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        // Trong SwiftUI: clockwise = false quét góc ngược lại (135 qua 180, 270 đến 45 = 270 độ trên đỉnh)
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

    public init(isHUDPresented: Binding<Bool> = .constant(false)) {
        self._isHUDPresented = isHUDPresented
    }

    public var body: some View {
        ZStack {
            // Nền tối mờ tạo độ tương phản trên StatusBar
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)

            // 1. Vòng cung Pin / RAM (Outer Battery / RAM Arc)
            outerGaugeArc

            // 2. Tâm Wi-Fi hoặc Tốc độ mạng thời gian thực (> 100 KB/s)
            centerNetworkIcon

            // 3. Các chấm sóng di động uốn cong ở đáy (Cellular Arc)
            bottomCellularDots
        }
        .frame(width: size, height: size)
        .scaleEffect(manager.scale)
        .opacity(manager.opacity)
        .contentShape(Circle())
        .onTapGesture(count: 2) {
            // Chạm đúp: Hoán đổi hiển thị Pin <-> RAM
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isShowingRAM.toggle()
            }
        }
        .onTapGesture(count: 1) {
            // Chạm 1 lần: Bật/tắt HUD tóm tắt phần cứng
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
            // Ray nền xám mờ
            GaugeArcShape()
                .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size - strokeWidth, height: size - strokeWidth)

            // Ray tiến trình thực tế
            GaugeArcShape()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(activeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size - strokeWidth, height: size - strokeWidth)
                .shadow(
                    color: (manager.isCharging && manager.enableBreathingGlow)
                        ? activeColor.opacity(isGlowBreathing ? 0.95 : 0.25)
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
            return Color.white.opacity(0.92)
        }
    }

    // MARK: - 2. Tâm Wi-Fi hoặc Tốc độ mạng
    private var centerNetworkIcon: some View {
        Group {
            if manager.autoSpeedSwitch && manager.downloadSpeedBytesPerSec > 100_000 {
                // Tốc độ mạng thời gian thực khi > 100 KB/s
                VStack(spacing: -1) {
                    Text(manager.downloadSpeedFormatted)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.25, green: 0.95, blue: 0.40))
                    Text("DL")
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundColor(.secondary)
                }
            } else if manager.isWifiConnected {
                // Biểu tượng Wi-Fi vector chuẩn
                wifiWavesIcon
            } else if manager.isCellularConnected {
                // Không có Wi-Fi, hiển thị 4G/LTE
                Text("4G")
                    .font(.system(size: 8.5, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
            } else {
                // Không có mạng
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
    }

    private var wifiWavesIcon: some View {
        Canvas { context, sz in
            let center = CGPoint(x: sz.width / 2.0, y: sz.height * 0.64)

            // Chấm gốc tâm Wi-Fi
            let dotRect = CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))

            // 2 vòng cung sóng Wi-Fi (trong & ngoài)
            let waveRadii: [CGFloat] = [3.8, 7.2]
            for r in waveRadii {
                var path = Path()
                path.addArc(center: center, radius: r, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                context.stroke(path, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - 3. Các chấm sóng di động ở đáy
    private var bottomCellularDots: some View {
        // Góc quét dọc theo đường tròn đáy từ trái qua phải (122 độ về 58 độ)
        let angles: [Double] = [122, 101, 79, 58]
        let radius = (size / 2.0) - (strokeWidth / 2.0)

        return ZStack {
            ForEach(0..<angles.count, id: \.self) { index in
                let angleRad = angles[index] * .pi / 180.0
                let x = (size / 2.0) + radius * CGFloat(cos(angleRad))
                let y = (size / 2.0) + radius * CGFloat(sin(angleRad))
                let isLit = index < manager.cellularBars

                Circle()
                    .fill(isLit ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 2.2, height: 2.2)
                    .position(x: x, y: y)
            }
        }
        .frame(width: size, height: size)
    }
}
