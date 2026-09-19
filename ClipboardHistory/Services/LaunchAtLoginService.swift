import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginControlling {
    func currentStatus() -> LaunchAtLoginStatus {
        LaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        let current = SMAppService.mainApp.status
        if enabled {
            guard current != .enabled, current != .requiresApproval else { return }
            do {
                try SMAppService.mainApp.register()
            } catch {
                if Self.isAlreadyRegistered(error) { return }
                throw error
            }
        } else {
            guard current != .notRegistered, current != .notFound else { return }
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                if Self.isNotRegistered(error) { return }
                throw error
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static let alreadyRegistered = 1
    private static let notRegistered = 3

    private static func isAlreadyRegistered(_ error: Error) -> Bool {
        isServiceError(error, code: alreadyRegistered)
    }

    private static func isNotRegistered(_ error: Error) -> Bool {
        isServiceError(error, code: notRegistered)
    }

    private static func isServiceError(_ error: Error, code: Int) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "SMAppServiceErrorDomain" && nsError.code == code
    }
}

private extension LaunchAtLoginStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        case .notRegistered:
            self = .notRegistered
        @unknown default:
            self = .notRegistered
        }
    }
}
