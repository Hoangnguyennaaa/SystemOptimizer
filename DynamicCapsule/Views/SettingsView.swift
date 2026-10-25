import SwiftUI

public struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var monitor = SystemMonitor.shared

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Thiết bị")) {
                    HStack {
                        Image(systemName: "iphone")
                        Text("Model")
                        Spacer()
                        Text("iPhone 7 Plus (A10 Fusion)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "gearshape")
                        Text("Phiên bản iOS")
                        Spacer()
                        Text("iOS 15.8.x")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "aspectratio")
                        Text("Tỷ lệ màn hình")
                        Spacer()
                        Text("16:9 (414 x 736 pt)")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Trạng thái giám sát thời gian thực")) {
                    HStack {
                        Text("RAM còn trống")
                        Spacer()
                        Text(String(format: "%.2f GB / 3.00 GB", monitor.ramUsage.freeGB))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Mức pin hiện tại")
                        Spacer()
                        Text("\(monitor.batteryLevel)% (\(monitor.isCharging ? "Đang sạc" : "Dùng pin"))")
                    }

                    HStack {
                        Text("Loại mạng kết nối")
                        Spacer()
                        Text(monitor.networkType.rawValue)
                    }

                    HStack {
                        Text("Tốc độ tải xuống (DL)")
                        Spacer()
                        Text(monitor.downloadSpeedString)
                    }
                }

                Section(header: Text("Hướng dẫn tương tác Capsule")) {
                    Text("• Chạm 1 lần (Tap): Mở rộng viên thuốc để xem thông tin chi tiết.")
                    Text("• Nhấn giữ (Long press): Mở bảng cài đặt này.")
                    Text("• Cửa sổ sử dụng cơ chế Hit-Testing xuyên thấu, không ảnh hưởng thao tác các ứng dụng khác.")
                }
            }
            .navigationTitle("Cấu hình DynamicCapsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
