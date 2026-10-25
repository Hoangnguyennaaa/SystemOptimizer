import SwiftUI

struct ContentView: View {
    @StateObject private var manager = DaemonManager()
    @State private var showingRestoreAlert = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Thông tin thiết bị")) {
                    HStack {
                        Image(systemName: "cpu")
                        Text("Apple A10 Fusion (3GB RAM)")
                        Spacer()
                        Text("iOS 15.8.x")
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(RiskLevel.allCases) { level in
                    let items = manager.daemons.filter { $0.riskLevel == level }
                    if !items.isEmpty {
                        Section(header: sectionHeader(for: level)) {
                            ForEach(items) { item in
                                daemonRow(for: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("SystemOptimizer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showingRestoreAlert = true
                    } label: {
                        Text("Khôi phục")
                    }
                    .disabled(manager.isExecuting)
                }
            }
            .alert("Khôi phục mặc định", isPresented: $showingRestoreAlert) {
                Button("Hủy", role: .cancel) { }
                Button("Xác nhận khôi phục", role: .destructive) {
                    manager.restoreAllDefaults()
                }
            } message: {
                Text("Thao tác này sẽ bật lại toàn bộ các daemon hệ thống đã bị tắt.")
            }
            .overlay {
                if manager.isExecuting {
                    ProgressView("Đang áp dụng thay đổi...")
                        .padding()
                        .background(Material.regular)
                        .cornerRadius(10)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for level: RiskLevel) -> some View {
        HStack {
            Circle()
                .fill(color(for: level))
                .frame(width: 8, height: 8)
            Text(level.rawValue)
                .font(.headline)
        }
    }

    private func color(for level: RiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .moderate: return .orange
        case .dangerous: return .red
        }
    }

    @ViewBuilder
    private func daemonRow(for item: DaemonItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)
                Spacer()
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                } else {
                    Toggle("", isOn: Binding(
                        get: { item.isEnabled },
                        set: { _ in manager.toggleDaemon(daemon: item) }
                    ))
                    .labelsHidden()
                    .disabled(manager.isExecuting)
                }
            }

            Text(item.descriptionText)
                .font(.subheadline)
                .foregroundColor(.primary)

            Text("Tác động: \(item.impactText)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
