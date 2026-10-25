import Foundation
import Darwin
import UIKit
import Network

public struct RAMUsage {
    public let freeBytes: UInt64
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public var freeGB: Double { Double(freeBytes) / 1_073_741_824.0 }
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    public var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
}

public enum NetworkType: String {
    case wifi = "WiFi"
    case cellular = "4G/LTE"
    case none = "Offline"
}

public final class SystemMonitor: ObservableObject {
    public static let shared = SystemMonitor()

    // Pin
    @Published public var batteryLevel: Int = 100
    @Published public var isCharging: Bool = false
    @Published public var batteryState: UIDevice.BatteryState = .unknown

    // RAM (A10 Fusion 3GB)
    @Published public var ramUsage: RAMUsage = RAMUsage(freeBytes: 0, usedBytes: 0, totalBytes: 0)

    // Mạng
    @Published public var networkType: NetworkType = .wifi
    @Published public var downloadSpeedString: String = "0 KB/s"
    @Published public var uploadSpeedString: String = "0 KB/s"

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.dynamiccapsule.network")
    private var timer: Timer?

    private var lastIBytes: UInt64 = 0
    private var lastOBytes: UInt64 = 0
    private var lastSampleTime: TimeInterval = 0

    private init() {
        setupBatteryMonitoring()
        setupNetworkMonitoring()
        startPeriodicUpdates()
    }

    // MARK: - Battery Monitoring
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBattery()

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBattery()
        }

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBattery()
        }
    }

    private func updateBattery() {
        let level = UIDevice.current.batteryLevel
        self.batteryLevel = level < 0 ? 100 : Int(level * 100)
        let state = UIDevice.current.batteryState
        self.batteryState = state
        self.isCharging = (state == .charging || state == .full)
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.usesInterfaceType(.wifi) {
                    self?.networkType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.networkType = .cellular
                } else {
                    self?.networkType = .none
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    // MARK: - Periodic Stats (RAM & Speed)
    private func startPeriodicUpdates() {
        updateRAM()
        updateNetworkSpeed()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRAM()
            self?.updateNetworkSpeed()
            self?.updateBattery()
        }
    }

    private func updateRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory

        if kerr == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let page = UInt64(pageSize > 0 ? pageSize : 16384)
            let free = UInt64(stats.free_count + stats.inactive_count) * page
            let used = total > free ? (total - free) : 0
            DispatchQueue.main.async {
                self.ramUsage = RAMUsage(freeBytes: free, usedBytes: used, totalBytes: total)
            }
        }
    }

    private func updateNetworkSpeed() {
        let (currentIBytes, currentOBytes) = getRawNetworkBytes()
        let now = Date().timeIntervalSince1970

        if lastSampleTime > 0 && now > lastSampleTime {
            let deltaT = now - lastSampleTime
            let deltaI = currentIBytes >= lastIBytes ? (currentIBytes - lastIBytes) : 0
            let deltaO = currentOBytes >= lastOBytes ? (currentOBytes - lastOBytes) : 0

            let speedInBytesPerSec = Double(deltaI) / deltaT
            let speedOutBytesPerSec = Double(deltaO) / deltaT

            DispatchQueue.main.async {
                self.downloadSpeedString = self.formatSpeed(bytesPerSec: speedInBytesPerSec)
                self.uploadSpeedString = self.formatSpeed(bytesPerSec: speedOutBytesPerSec)
            }
        }

        lastIBytes = currentIBytes
        lastOBytes = currentOBytes
        lastSampleTime = now
    }

    private func getRawNetworkBytes() -> (ibytes: UInt64, obytes: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIBytes: UInt64 = 0
        var totalOBytes: UInt64 = 0

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)
            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (name.hasPrefix("en") || name.hasPrefix("pdp_ip")) {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalIBytes += UInt64(networkData.pointee.ifi_ibytes)
                    totalOBytes += UInt64(networkData.pointee.ifi_obytes)
                }
            }
        }
        return (totalIBytes, totalOBytes)
    }

    private func formatSpeed(bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        }
    }
}
