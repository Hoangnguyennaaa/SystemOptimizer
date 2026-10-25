import Foundation

enum RiskLevel: String, CaseIterable, Identifiable {
    case safe = "An toàn"
    case moderate = "Cân nhắc"
    case dangerous = "Nguy hiểm (Cấm tắt)"

    var id: String { rawValue }
}

struct DaemonItem: Identifiable, Equatable {
    let id: String
    let name: String
    let descriptionText: String
    let impactText: String
    let riskLevel: RiskLevel
    var isEnabled: Bool
    var isLocked: Bool { riskLevel == .dangerous }
}
