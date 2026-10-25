import Foundation
import Darwin
import UIKit
import Network
import CoreTelephony

public enum StatusPosition: String, CaseIterable, Identifiable {
    case topRight = "Góc phải"
    case topLeft = "Góc trái"
    case center = "Chính giữa"

    public var id: String { rawValue }
}

public final class SystemStatusManager: ObservableObject {
    public static let shared = SystemStatusManager()

    // Cấu hình hiển thị (Lưu trữ và đồng bộ UI)
    @Published public var position: StatusPosition = .topRight
    @Published public var scale: CGFloat = 1.0
    @Published public var opacity: Double = 0.95
    @Published public var enableBreathingGlow: Bool = true
    @Published public var autoSpeedSwitch: Bool = true

    // Trạng thái phần cứng thời gian thực
    @Published public var batteryLevel: Double = 1.0       // 0.0 -> 1.0
    @Published public var isCharging: Bool = false
    @Published public var isLowPowerMode: Bool = false

    @Published public var ramUsedPercent: Double = 0.5    // 0.0 -> 1.0
    @Published public var ramFreeGB: Double = 1.5
    @Published public var ramTotalGB: Double = 3.0

    @Published public var isWifiConnected: Bool = true
    @Published public var isCellularConnected: Bool = false
    @Published public var cellularBars: Int = 4            // 0 -> 5 chấm
    @Published public var downloadSpeedBytesPerSec: Double = 0.0
    @Published public var downloadSpeedFormatted: String = ""

    @Published public var thermalStateDescription: String = "Bình thường"

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.compactstatusbar.netmonitor")
    private var updateTimer: Timer?

    private var lastIBytes: UInt64 = 0
    private var lastSampleTime: TimeInterval = 0

    private init() {
        loadSettings()
        setupBatteryMonitoring()
        setupNetworkMonitoring()
        startPeriodicUpdate()
    }

    // MARK: - Quản lý cài đặt
    public func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(position.rawValue, forKey: "csb_position")
        defaults.set(Double(scale), forKey: "csb_scale")
        defaults.set(opacity, forKey: "csb_opacity")
        defaults.set(enableBreathingGlow, forKey: "csb_glow")
        defaults.set(autoSpeedSwitch, forKey: "csb_autospeed")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let posStr = defaults.string(forKey: "csb_position"), let pos = StatusPosition(rawValue: posStr) {
            self.position = pos
        }
        let savedScale = defaults.double(forKey: "csb_scale")
        if savedScale > 0.5 { self.scale = CGFloat(savedScale) }

        let savedOpacity = defaults.double(forKey: "csb_opacity")
        if savedOpacity > 0.1 { self.opacity = savedOpacity }

        if defaults.object(forKey: "csb_glow") != nil {
            self.enableBreathingGlow = defaults.bool(forKey: "csb_glow")
        }
        if defaults.object(forKey: "csb_autospeed") != nil {
            self.autoSpeedSwitch = defaults.bool(forKey: "csb_autospeed")
        }
    }

    // MARK: - Battery Monitor
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryState()

        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBatteryState()
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateBatteryState()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func updateBatteryState() {
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel < 0 ? 1.0 : Double(rawLevel)
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Chỉ re-render nếu có giá trị thay đổi thực tế
        if abs(self.batteryLevel - level) >= 0.01 || self.isCharging != charging || self.isLowPowerMode != lowPower {
            self.batteryLevel = level
            self.isCharging = charging
            self.isLowPowerMode = lowPower
        }
    }

    // MARK: - Network Monitor
    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isWifiConnected = path.usesInterfaceType(.wifi)
                self?.isCellularConnected = path.usesInterfaceType(.cellular)
                self?.cellularBars = path.usesInterfaceType(.cellular) ? 4 : (path.usesInterfaceType(.wifi) ? 5 : 1)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    // MARK: - Periodic Loop (1s Update)
    private func startPeriodicUpdate() {
        pollHardware()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollHardware()
        }
    }

    private func pollHardware() {
        updateBatteryState()
        updateRAM()
        updateNetworkTraffic()
        updateThermalState()
    }

    // MARK: - Mach Kernel RAM Stats (A10 Fusion 3GB)
    private func updateRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        if kerr == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let page = UInt64(pageSize > 0 ? pageSize : 16384)
            let freeBytes = UInt64(stats.free_count + stats.inactive_count) * page
            let usedBytes = totalBytes > freeBytes ? (totalBytes - freeBytes) : 0

            let usedRatio = Double(usedBytes) / Double(totalBytes)
            let freeGB = Double(freeBytes) / 1_073_741_824.0
            let totalGB = Double(totalBytes) / 1_073_741_824.0

            if abs(self.ramUsedPercent - usedRatio) > 0.01 {
                DispatchQueue.main.async {
                    self.ramUsedPercent = min(max(usedRatio, 0.0), 1.0)
                    self.ramFreeGB = freeGB
                    self.ramTotalGB = totalGB
                }
            }
        }
    }

    // MARK: - Real-time Network Traffic (getifaddrs)
    private func updateNetworkTraffic() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var currentIBytes: UInt64 = 0
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)
            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (name.hasPrefix("en") || name.hasPrefix("pdp_ip")) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    currentIBytes += UInt64(networkData.pointee.ifi_ibytes)
                }
            }
        }

        let now = Date().timeIntervalSince1970
        if lastSampleTime > 0 && now > lastSampleTime {
            let deltaT = now - lastSampleTime
            let deltaI = currentIBytes >= lastIBytes ? (currentIBytes - lastIBytes) : 0
            let speed = Double(deltaI) / deltaT

            DispatchQueue.main.async {
                self.downloadSpeedBytesPerSec = speed
                if speed >= 1_048_576.0 {
                    self.downloadSpeedFormatted = String(format: "%.1fM", speed / 1_048_576.0)
                } else if speed >= 1024.0 {
                    self.downloadSpeedFormatted = String(format: "%.0fK", speed / 1024.0)
                } else {
                    self.downloadSpeedFormatted = "0K"
                }
            }
        }

        lastIBytes = currentIBytes
        lastSampleTime = now
    }

    // MARK: - Thermal State
    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let desc: String
        switch state {
        case .nominal: desc = "Mát mẻ"
        case .fair: desc = "Bình thường"
        case .serious: desc = "Ấm / Nóng"
        case .critical: desc = "Quá nhiệt"
        @unknown default: desc = "Ổn định"
        }
        if self.thermalStateDescription != desc {
            DispatchQueue.main.async {
                self.thermalStateDescription = desc
            }
        }
    }

    // MARK: - Khóa màn hình (Lock Device via Notification / SpringBoard)
    public func lockDevice() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Phát tín hiệu khóa màn hình tới SpringBoard
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName("com.apple.springboard.lock" as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }
}
