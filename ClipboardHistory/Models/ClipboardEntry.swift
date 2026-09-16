import Foundation

enum ClipboardKind: String, CaseIterable, Identifiable, Sendable {
    case text
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .image: "photo"
        }
    }
}

struct ClipboardEntry: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var text: String = ""
    var copiedAt = Date()
    var imagePNG: Data?

    var kind: ClipboardKind { imagePNG == nil ? .text : .image }

    var preview: String {
        String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ↵ ")
    }

    init(id: UUID = UUID(), text: String, imagePNG: Data? = nil, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.imagePNG = imagePNG
        self.copiedAt = copiedAt
    }

    init(imagePNG: Data, copiedAt: Date = Date()) {
        self.init(text: "", imagePNG: imagePNG, copiedAt: copiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, text, copiedAt
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
