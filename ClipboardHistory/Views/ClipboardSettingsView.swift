import AppKit
import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(ClipboardStore.self) private var store
    @Environment(FileStagingStore.self) private var files
    @Environment(LaunchAtLoginStore.self) private var launchAtLogin
    @State private var didCopyCachePath: Bool?
    @State private var isClearingCache = false
    @State private var cacheClearResult: CacheClearResult?
    var onOpenAbout: () -> Void = {}

    private var cacheDirectoryPath: String {
        HistoryRepository.cacheDirectoryURL().path(percentEncoded: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            Form {
                Section {
                    Toggle("开机自启动", isOn: Binding(
                        get: { launchAtLogin.isToggleOn },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .accessibilityHint("登录 Mac 时自动启动 Barclip")
                    if let message = launchAtLogin.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(launchAtLogin.status == .requiresApproval ? Color.secondary : Color.red)
                        if launchAtLogin.status == .requiresApproval {
                            Button("打开登录项设置") {
                                launchAtLogin.openLoginItemsSettings()
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader(
                        title: "启动",
                        explanation: "登录 Mac 时自动启动 Barclip。首次打开可能需要在系统设置的登录项中允许。从 Xcode 或非正式安装位置运行时，系统可能拒绝注册。"
                    )
                }
                Section {
                    CapacitySettingRow(
                        title: "文本",
                        value: Binding(
                            get: { store.textCapacity },
                            set: { store.setCapacity($0, for: .text) }
                        )
                    )
                    .disabled(store.isLoading || store.storageError == .load)
                    CapacitySettingRow(
                        title: "图片",
                        value: Binding(
                            get: { store.imageCapacity },
                            set: { store.setCapacity($0, for: .image) }
                        )
                    )
                    .disabled(store.isLoading || store.storageError == .load)
                    CapacitySettingRow(
                        title: "文件",
                        value: Binding(
                            get: { files.capacity },
                            set: { files.setCapacity($0) }
                        )
                    )
                    .disabled(files.isLoading || files.storageError == .load)
                } header: {
                    SettingsSectionHeader(title: "保留条数", explanation: "文本、图片和文件可分别设置保留数量，范围为 1 到 200 条。超过上限时移除最早的记录，调小容量立即生效。")
                }
                Section {
                    Picker("历史记录", selection: Binding(
                        get: { store.retention },
                        set: { value in
                            store.setRetention(value)
                            files.setRetention(value)
                        }
                    )) {
                        ForEach(RetentionPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .disabled(store.isLoading || store.storageError == .load)
                } header: {
                    SettingsSectionHeader(title: "保存策略", explanation: "选择重启后保留时，文本、图片和文件位置保存在用户资料库的 Application Support/Barclip 中。删除应用不会删除这些记录。切换为退出后清空会删除当前磁盘缓存，当前记录仍可使用。旧版缓存迁移后保留在原位置。")
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("文件夹地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 8) {
                            Text(cacheDirectoryPath)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("缓存文件夹地址 \(cacheDirectoryPath)")
                            Button {
                                didCopyCachePath = store.copyCacheDirectoryPath()
                            } label: {
                                Label("复制地址", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                            }
                            .help("复制地址")
                        }
                        if let didCopyCachePath {
                            Text(didCopyCachePath ? "地址已复制" : "复制失败，请重试。")
                                .font(.caption)
                                .foregroundStyle(didCopyCachePath ? Color.secondary : Color.red)
                        }
                    }
                    Button(role: .destructive) {
                        presentClearDiskCacheConfirmation()
                    } label: {
                        Label(
                            isClearingCache ? "正在清理…" : "一键清理全部磁盘缓存",
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isClearingCache || store.isLoading || files.isLoading)
                    if let cacheClearResult {
                        Text(cacheClearResult.message)
                            .font(.caption)
                            .foregroundStyle(cacheClearResult == .succeeded ? Color.secondary : Color.red)
                    }
                } header: {
                    SettingsSectionHeader(title: "磁盘缓存", explanation: "点击复制按钮复制此地址，在 Finder 的“前往文件夹”中打开；也可在下方一键清理 Barclip 的全部文本、图片和文件暂存缓存。")
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300, maxHeight: .infinity)
            aboutFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private func presentClearDiskCacheConfirmation() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "清理全部磁盘缓存？")
        alert.informativeText = String(localized: "这会删除 Barclip 中的全部文本、图片和文件暂存记录，但不会删除原文件，也不会重置其他设置。")
        alert.addButton(withTitle: String(localized: "取消"))
        alert.addButton(withTitle: String(localized: "全部清理"))
        alert.buttons[1].hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { await clearAllDiskCache() }
    }

    private func clearAllDiskCache() async {
        isClearingCache = true
        cacheClearResult = nil
        let succeeded = await DiskCacheCleaner.clear(clipboard: store, files: files)
        cacheClearResult = succeeded ? .succeeded : .failed
        isClearingCache = false
    }

    private var aboutFooter: some View {
        Button(action: onOpenAbout) {
            VStack(spacing: 4) {
                Text("程序版本 \(AppInfo.shortVersion)")
                Text("关于我们")
                Text(AppInfo.copyright)
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(AboutFooterButtonStyle())
        .help("程序版本和关于我们")
        .accessibilityLabel("程序版本 \(AppInfo.shortVersion)，关于我们，\(AppInfo.copyright)")
        .accessibilityHint("打开程序版本和关于我们")
    }
}

private struct CapacitySettingRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Int($0.rounded()) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 54, alignment: .leading)
            Slider(
                value: sliderValue,
                in: Double(ClipboardStore.capacityRange.lowerBound)...Double(ClipboardStore.capacityRange.upperBound)
            )
            .accessibilityLabel(Text(title) + Text("保留条数"))
            TextField("保留条数", value: $value, format: .number.grouping(.never))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .accessibilityLabel(Text(title) + Text("保留条数"))
        }
    }
}

@MainActor
enum DiskCacheCleaner {
    static func clear(clipboard: ClipboardStore, files: FileStagingStore) async -> Bool {
        clipboard.clear()
        files.clear()
        await clipboard.finishPendingSave()
        await files.finishPendingSave()
        let wiped = await clipboard.wipeDiskCache()
        if wiped {
            files.noteDiskCacheWiped()
        }
        return wiped
    }
}

private enum CacheClearResult {
    case succeeded
    case failed

    var message: LocalizedStringKey {
        switch self {
        case .succeeded: "已清理全部磁盘缓存。"
        case .failed: "部分磁盘缓存清理失败，请重试。"
        }
    }
}

private struct SettingsSectionHeader: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    @State private var isShowingExplanation = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button {
                isShowingExplanation.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title) + Text("说明"))
            .help("显示说明")
            .popover(isPresented: $isShowingExplanation, arrowEdge: .trailing) {
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(16)
                    .frame(width: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AboutFooterButtonBody(configuration: configuration)
    }
}

private struct AboutFooterButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.02 : 1))
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
    }
}
