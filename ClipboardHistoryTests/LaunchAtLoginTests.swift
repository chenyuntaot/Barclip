import XCTest
@testable import ClipboardHistory

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testEnablingRegistersAndClearsMessage() {
        let service = FakeLaunchAtLoginService()
        let store = LaunchAtLoginStore(service: service)
        XCTAssertFalse(store.isToggleOn)
        XCTAssertNil(store.message)
        store.setEnabled(true)
        XCTAssertEqual(service.setEnabledCalls, [true])
        XCTAssertEqual(store.status, .enabled)
        XCTAssertTrue(store.isToggleOn)
        XCTAssertNil(store.message)
    }

    func testDisablingUnregistersPendingOrEnabledItem() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let store = LaunchAtLoginStore(service: service)
        store.setEnabled(false)
        XCTAssertEqual(service.setEnabledCalls, [false])
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertFalse(store.isToggleOn)

        service.status = .requiresApproval
        store.refresh()
        XCTAssertTrue(store.isToggleOn)
        store.setEnabled(false)
        XCTAssertEqual(service.setEnabledCalls, [false, false])
        XCTAssertEqual(store.status, .notRegistered)
    }

    func testRequiresApprovalKeepsToggleOnAndCanOpenSettings() {
        let service = FakeLaunchAtLoginService(statusAfterSet: .requiresApproval)
        let store = LaunchAtLoginStore(service: service)
        store.setEnabled(true)
        XCTAssertEqual(store.status, .requiresApproval)
        XCTAssertTrue(store.isToggleOn)
        XCTAssertEqual(store.message, String(localized: "系统尚未允许此登录项。请在系统设置中允许 Barclip。"))
        store.openLoginItemsSettings()
        XCTAssertEqual(service.openSettingsCount, 1)
        store.setEnabled(true)
        XCTAssertEqual(service.openSettingsCount, 2)
        XCTAssertEqual(service.setEnabledCalls, [true])
    }

    func testNotFoundDoesNotShowInstallLocationMessage() {
        let existing = LaunchAtLoginStore(service: FakeLaunchAtLoginService(status: .notFound))
        XCTAssertNil(existing.message)
        XCTAssertFalse(existing.isToggleOn)

        let service = FakeLaunchAtLoginService(statusAfterSet: .notFound)
        let store = LaunchAtLoginStore(service: service)
        store.setEnabled(true)
        XCTAssertEqual(store.status, .notFound)
        XCTAssertFalse(store.isToggleOn)
        XCTAssertNil(store.message)
    }

    func testServiceFailureShowsRetryMessageAndRefreshesStatus() {
        let service = FakeLaunchAtLoginService()
        service.error = TestLaunchAtLoginError.updateFailed
        let store = LaunchAtLoginStore(service: service)
        store.setEnabled(true)
        XCTAssertEqual(service.setEnabledCalls, [true])
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertEqual(store.message, String(localized: "无法更新开机启动，请重试。"))
        XCTAssertFalse(store.isToggleOn)
    }

    func testRefreshReadsSystemStatusWithoutWriting() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let store = LaunchAtLoginStore(service: service)
        service.status = .notRegistered
        store.refresh()
        XCTAssertTrue(service.setEnabledCalls.isEmpty)
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertNil(store.message)
    }
}

@MainActor
final class FakeLaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var statusAfterSet: LaunchAtLoginStatus?
    var error: Error?
    private(set) var setEnabledCalls: [Bool] = []
    private(set) var openSettingsCount = 0

    init(status: LaunchAtLoginStatus = .notRegistered, statusAfterSet: LaunchAtLoginStatus? = nil) {
        self.status = status
        self.statusAfterSet = statusAfterSet
    }

    func currentStatus() -> LaunchAtLoginStatus { status }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let error { throw error }
        status = statusAfterSet ?? (enabled ? .enabled : .notRegistered)
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

private enum TestLaunchAtLoginError: Error {
    case updateFailed
}
