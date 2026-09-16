import Foundation

struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    let text: String
    var copiedAt = Date()

    var preview: String {
        String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ↵ ")
    }
}

enum RetentionPolicy: String, CaseIterable, Identifiable {
    case session
    case persistent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .session: "退出后清空"
        case .persistent: "重启后保留"
        }
    }
}
