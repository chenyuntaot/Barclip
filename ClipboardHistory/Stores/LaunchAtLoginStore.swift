import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LaunchAtLoginStore {
    private(set) var status: LaunchAtLoginStatus
    private(set) var message: String?

    var isToggleOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    @ObservationIgnored private let service: any LaunchAtLoginControlling
    private static let logger = Logger(subsystem: "local.ClipboardHistory", category: "LaunchAtLogin")

    init(service: any LaunchAtLoginControlling = SystemLaunchAtLoginService()) {
        self.service = service
        status = service.currentStatus()
        message = Self.message(for: status, didFail: false)
    }

    func refresh() {
        status = service.currentStatus()
        message = Self.message(for: status, didFail: false)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled && status == .requiresApproval {
            service.openLoginItemsSettings()
            return
        }
        do {
            try service.setEnabled(enabled)
            status = service.currentStatus()
            message = Self.message(for: status, didFail: false)
        } catch {
            Self.logger.error("Unable to update login item")
            status = service.currentStatus()
            message = Self.message(for: status, didFail: true)
        }
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    private static func message(for status: LaunchAtLoginStatus, didFail: Bool) -> String? {
        switch status {
        case .enabled:
            nil
        case .notRegistered:
            didFail ? String(localized: "无法更新开机启动，请重试。") : nil
        case .requiresApproval:
            String(localized: "系统尚未允许此登录项。请在系统设置中允许 Barclip。")
        case .notFound:
            String(localized: "当前安装位置无法注册开机启动。请将 Barclip 放到应用程序文件夹后再试。")
        }
    }
}
