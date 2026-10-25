import Foundation
import Darwin

final class DaemonManager: ObservableObject {
    @Published var daemons: [DaemonItem] = []
    @Published var isExecuting: Bool = false
    @Published var statusMessage: String = ""

    private var rootHelperPath: String {
        Bundle.main.bundlePath + "/RootHelper"
    }

    init() {
        loadDaemonList()
        refreshAllStatuses()
    }

    func daemons(for level: RiskLevel) -> [DaemonItem] {
        daemons.filter { $0.riskLevel == level }
    }

    func loadDaemonList() {
        self.daemons = [
            // Nhóm 1: Rất an toàn
            DaemonItem(
                id: "com.apple.CrashHouseKeeping",
                name: "Crash HouseKeeping",
                descriptionText: "Dọn dẹp nhật ký sự cố ứng dụng.",
                impactText: "Không ảnh hưởng sử dụng. Giảm ghi bộ nhớ flash.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.DumpPanic",
                name: "Dump Panic",
                descriptionText: "Ghi lại nhật ký panic hệ thống khi kernel crash.",
                impactText: "Tắt an toàn. Không gửi dữ liệu chẩn đoán về Apple.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.ReportCrash",
                name: "Report Crash",
                descriptionText: "Bộ dịch vụ theo dõi và phân tích tiến trình ứng dụng crash.",
                impactText: "Tiết kiệm RAM và chu kỳ CPU A10 khi có app nền lỗi.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.tipsd",
                name: "Tips Daemon",
                descriptionText: "Hiển thị mẹo sử dụng trên iOS.",
                impactText: "Không ảnh hưởng tính năng. Giải phóng bộ nhớ RAM.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.gamecenter.daemon",
                name: "Game Center",
                descriptionText: "Đồng bộ thành tích, bảng xếp hạng Game Center.",
                impactText: "Nếu không dùng Game Center, tắt sẽ giải phóng tài nguyên nền.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.voicemail",
                name: "Visual Voicemail",
                descriptionText: "Thư thoại hình ảnh.",
                impactText: "Nhà mạng không hỗ trợ Visual Voicemail tắt sẽ tiết kiệm pin.",
                riskLevel: .safe,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.homed",
                name: "HomeKit Daemon",
                descriptionText: "Dịch vụ điều khiển phụ kiện nhà thông minh HomeKit.",
                impactText: "Tắt nếu không sử dụng thiết bị Smarthome.",
                riskLevel: .safe,
                isEnabled: true
            ),

            // Nhóm 2: Cân nhắc
            DaemonItem(
                id: "com.apple.CoreLocation",
                name: "CoreLocation",
                descriptionText: "Dịch vụ định vị vệ tinh và mạng.",
                impactText: "Tắt sẽ ngắt GPS nền, Maps và định vị ứng dụng không hoạt động.",
                riskLevel: .moderate,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.Passbook",
                name: "Passbook & Apple Pay",
                descriptionText: "Dịch vụ Ví và thanh toán thẻ Apple Pay.",
                impactText: "Tắt sẽ không dùng được Apple Pay hoặc thẻ thành viên.",
                riskLevel: .moderate,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.assistantd",
                name: "Siri Assistant",
                descriptionText: "Dịch vụ phản hồi giọng nói Siri và gợi ý tìm kiếm.",
                impactText: "Tắt Siri giải phóng hơn 50MB RAM nhưng mất tính năng gọi 'Hey Siri'.",
                riskLevel: .moderate,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.cloudphotod",
                name: "iCloud Photos Sync",
                descriptionText: "Đồng bộ thư viện ảnh lên iCloud.",
                impactText: "Ảnh chụp sẽ không tải lên iCloud cho đến khi bật lại.",
                riskLevel: .moderate,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.itunesstored",
                name: "iTunes Store Daemon",
                descriptionText: "Xử lý mua hàng in-app, tải ứng dụng từ App Store.",
                impactText: "Tắt có thể làm gián đoạn cập nhật app và thanh toán Store.",
                riskLevel: .moderate,
                isEnabled: true
            ),

            // Nhóm 3: Nguy hiểm (Hệ thống)
            DaemonItem(
                id: "com.apple.commcenter",
                name: "CommCenter",
                descriptionText: "Quản lý modem băng cơ sở (Baseband), sóng di động, SIM và cuộc gọi.",
                impactText: "TUYỆT ĐỐI KHÔNG TẮT. Mất sóng hoàn toàn hoặc văng màn hình kích hoạt.",
                riskLevel: .dangerous,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.backboardd",
                name: "Backboardd",
                descriptionText: "Tiến trình điều khiển tín hiệu cảm ứng và chuyển tiếp sự kiện phần cứng.",
                impactText: "TUYỆT ĐỐI KHÔNG TẮT. Màn hình liệt cảm ứng, máy rơi vào Respring loop.",
                riskLevel: .dangerous,
                isEnabled: true
            ),
            DaemonItem(
                id: "com.apple.SpringBoard",
                name: "SpringBoard",
                descriptionText: "Trình quản lý giao diện chính (Home screen, Lock screen, Dock).",
                impactText: "TUYỆT ĐỐI KHÔNG TẮT. Hệ thống không thể hiển thị giao diện.",
                riskLevel: .dangerous,
                isEnabled: true
            )
        ]
    }

    private func executeHelper(args: [String]) -> (status: Int32, output: String) {
        var pid: pid_t = 0
        var pipeFD: [Int32] = [0, 0]
        pipe(&pipeFD)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipeFD[1], 1)
        posix_spawn_file_actions_addclose(&fileActions, pipeFD[0])

        let argv: [UnsafeMutablePointer<CChar>?] = ([rootHelperPath] + args).map { strdup($0) } + [nil]

        let spawnResult = posix_spawn(&pid, rootHelperPath, &fileActions, nil, argv, nil)
        argv.forEach { free($0) }
        posix_spawn_file_actions_destroy(&fileActions)
        close(pipeFD[1])

        guard spawnResult == 0 else {
            close(pipeFD[0])
            return (-1, "posix_spawn failed: \(spawnResult)")
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        let readBytes = read(pipeFD[0], buffer, 4096)
        close(pipeFD[0])

        let out = readBytes > 0 ? (String(bytes: UnsafeBufferPointer(start: buffer, count: readBytes), encoding: .utf8) ?? "") : ""
        buffer.deallocate()

        let exitCode = (status >> 8) & 0xff
        return (exitCode, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func refreshAllStatuses() {
        for index in daemons.indices {
            let daemon = daemons[index]
            if daemon.isLocked { continue }
            let res = executeHelper(args: ["status", daemon.id])
            if res.status == 0 {
                daemons[index].isEnabled = (res.output == "1")
            }
        }
    }

    func toggleDaemon(daemon: DaemonItem) {
        guard !daemon.isLocked else { return }
        isExecuting = true
        let targetAction = daemon.isEnabled ? "disable" : "enable"

        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.executeHelper(args: [targetAction, daemon.id])
            DispatchQueue.main.async {
                self.isExecuting = false
                if res.status == 0 {
                    if let idx = self.daemons.firstIndex(where: { $0.id == daemon.id }) {
                        self.daemons[idx].isEnabled.toggle()
                    }
                    self.statusMessage = "Đã cập nhật \(daemon.name)"
                } else {
                    self.statusMessage = "Lỗi khi cập nhật \(daemon.name)"
                }
            }
        }
    }

    func restoreAllDefaults() {
        isExecuting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.executeHelper(args: ["restore"])
            DispatchQueue.main.async {
                self.isExecuting = false
                self.refreshAllStatuses()
                self.statusMessage = res.status == 0 ? "Đã khôi phục toàn bộ mặc định" : "Lỗi khôi phục"
            }
        }
    }
}
