import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        Form {
            Section("历史容量") {
                Picker("保留条数", selection: Binding(
                    get: { store.capacity }, set: { store.setCapacity($0) }
                )) {
                    ForEach(ClipboardStore.capacityOptions, id: \.self) { capacity in
                        Text("\(capacity) 条").tag(capacity)
                    }
                }
                Text("超过上限时移除最早的记录，调小容量立即生效。")
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
                Text("选择重启后保留时，文本会写进应用包内。把应用移到废纸篓会一起删掉这些记录。切换为退出后清空会删除磁盘缓存，当前记录仍可使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}
