import Foundation
import Darwin
import UIKit
import Network
import AVFoundation

public enum StatusPosition: String, CaseIterable, Identifiable {
    case coverStock = "Đè che Pin gốc"
    case topRight = "Góc trên phải"
    case topLeft = "Góc trên trái"
    case center = "Chính giữa"

    public var id: String { rawValue }
}

public final class SystemStatusManager: ObservableObject {
    public static let shared = SystemStatusManager()

    // 1. Công tắc kích hoạt dịch vụ
    @Published public var isOverlayActive: Bool = true {
        didSet {
            saveSettings()
            if isOverlayActive {
                startSilentAudio()
            } else {
                stopSilentAudio()
            }
        }
    }

    // 2. Cấu hình hiển thị
    @Published public var position: StatusPosition = .coverStock
    @Published public var scale: CGFloat = 1.0
    @Published public var opacity: Double = 1.0
    @Published public var enableBreathingGlow: Bool = true
    @Published public var autoSpeedSwitch: Bool = true

    // 3. Trạng thái phần cứng thời gian thực
    @Published public var batteryLevel: Double = 1.0
    @Published public var isCharging: Bool = false
    @Published public var isLowPowerMode: Bool = false

    @Published public var ramUsedPercent: Double = 0.5
    @Published public var ramFreeGB: Double = 1.5
    @Published public var ramTotalGB: Double = 3.0

    @Published public var isWifiConnected: Bool = true
    @Published public var isCellularConnected: Bool = false
    @Published public var cellularBars: Int = 4
    @Published public var downloadSpeedBytesPerSec: Double = 0.0
    @Published public var downloadSpeedFormatted: String = ""

    @Published public var thermalStateDescription: String = "Bình thường"

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.compactstatusbar.netmonitor")
    private var updateTimer: Timer?
    private var audioPlayer: AVAudioPlayer?

    private var lastIBytes: UInt64 = 0
    private var lastSampleTime: TimeInterval = 0

    private init() {
        loadSettings()
        setupBatteryMonitoring()
        setupNetworkMonitoring()
        startPeriodicUpdate()
        if isOverlayActive {
            startSilentAudio()
        }
    }

    // MARK: - Chạy ngầm vĩnh viễn (Silent Audio Loop cho iOS 15)
    public func startSilentAudio() {
        guard audioPlayer == nil || !audioPlayer!.isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let wavData = createSilentWavData()
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.0
            audioPlayer?.play()
        } catch {
            print("[CompactStatusBar] Audio keep-alive error: \(error)")
        }
    }

    public func stopSilentAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func createSilentWavData() -> Data {
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // Size 36
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // 16
        data.append(contentsOf: [0x01, 0x00])             // PCM
        data.append(contentsOf: [0x01, 0x00])             // 1 channel
        data.append(contentsOf: [0x44, 0xac, 0x00, 0x00]) // 44100 Hz
        data.append(contentsOf: [0x88, 0x58, 0x01, 0x00]) // 88200 bps
        data.append(contentsOf: [0x02, 0x00])             // 2 align
        data.append(contentsOf: [0x10, 0x00])             // 16 bit
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // 0 bytes
        return data
    }

    // MARK: - Quản lý cài đặt
    public func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isOverlayActive, forKey: "csb_active")
        defaults.set(position.rawValue, forKey: "csb_position")
        defaults.set(Double(scale), forKey: "csb_scale")
        defaults.set(opacity, forKey: "csb_opacity")
        defaults.set(enableBreathingGlow, forKey: "csb_glow")
        defaults.set(autoSpeedSwitch, forKey: "csb_autospeed")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "csb_active") != nil {
            self.isOverlayActive = defaults.bool(forKey: "csb_active")
        }
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

    // MARK: - Periodic Loop (1s)
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

    // MARK: - Khóa màn hình & Respring
    public func lockDevice() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName("com.apple.springboard.lock" as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }

    public func respring() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Gửi lệnh khởi động lại SpringBoard
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName("respring" as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)

        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/usr/bin/killall"), strdup("-9"), strdup("SpringBoard"), nil]
        posix_spawn(&pid, "/usr/bin/killall", nil, nil, argv, nil)
        argv.forEach { free($0) }
    }
}
