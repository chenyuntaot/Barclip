import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(ClipboardStore.self) private var store
    @Environment(FileStagingStore.self) private var files
    @State private var didCopyCachePath: Bool?
    var onOpenAbout: () -> Void = {}

    private var cacheDirectoryPath: String {
        HistoryRepository.cacheDirectoryURL().path(percentEncoded: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("保留条数", selection: Binding(
                        get: { store.capacity },
                        set: { value in
                            store.setCapacity(value)
                            files.setCapacity(value)
                        }
                    )) {
                        ForEach(ClipboardStore.capacityOptions, id: \.self) { capacity in
                            Text("\(capacity) 条").tag(capacity)
                        }
                    }
                    .disabled(store.isLoading || store.storageError == .load)
                } header: {
                    SettingsSectionHeader(title: "历史容量", explanation: "文本、图片和文件各自保留该数量。超过上限时移除最早的记录，调小容量立即生效。")
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
                } header: {
                    SettingsSectionHeader(title: "磁盘缓存", explanation: "点击复制按钮复制此地址，在 Finder 的“前往文件夹”中打开后手动清理。")
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300, maxHeight: .infinity)
            aboutFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
