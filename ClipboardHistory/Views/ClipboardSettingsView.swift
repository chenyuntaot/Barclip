import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(ClipboardStore.self) private var store
    var onOpenAbout: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("历史容量") {
                    Picker("保留条数", selection: Binding(
                        get: { store.capacity }, set: { store.setCapacity($0) }
                    )) {
                        ForEach(ClipboardStore.capacityOptions, id: \.self) { capacity in
                            Text("\(capacity) 条").tag(capacity)
                        }
                    }
                    Text("文本和图片各自保留该数量。超过上限时移除最早的记录，调小容量立即生效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("保存策略") {
                    Picker("历史记录", selection: Binding(
                        get: { store.retention }, set: { store.setRetention($0) }
                    )) {
                        ForEach(RetentionPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Text("选择重启后保留时，文本和图片会写进应用包内。把应用移到废纸篓会一起删掉这些记录。切换为退出后清空会删除磁盘缓存，当前记录仍可使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300)
            aboutFooter
        }
        .frame(minHeight: 360)
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
