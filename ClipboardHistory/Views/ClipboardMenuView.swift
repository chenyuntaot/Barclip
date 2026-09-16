import SwiftUI

struct ClipboardMenuView: View {
    @Environment(ClipboardStore.self) private var store
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("剪贴板历史", systemImage: "clipboard").font(.headline)
                Spacer()
                Text("\(store.entries.count) / \(store.capacity)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            if store.accessDenied {
                Label("剪贴板访问被拒绝，请在系统设置中允许此应用读取剪贴板。", systemImage: "lock")
                    .font(.callout)
                Button("重新检查", action: store.retry)
            } else if let message = store.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                if message.hasPrefix("无法读取") {
                    Button("重试", action: store.retry)
                }
            }
            if let error = store.storageError {
                Text(error.message).font(.caption).foregroundStyle(.red)
                Button("重试缓存操作") {
                    Task { await store.retryStorage() }
                }
                .disabled(store.isLoading)
            }
            if showsSettings {
                ClipboardSettingsView().disabled(store.isLoading || store.storageError == .load)
            } else if store.isLoading {
                ProgressView("正在读取历史…").frame(maxWidth: .infinity).frame(height: 220)
            } else if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.largeTitle).foregroundStyle(.secondary)
                    Text("暂无历史记录").font(.headline)
                    Text("复制一段文本后，它会出现在这里。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.entries) { entry in
                            Button { store.copy(entry) } label: {
                                HStack(alignment: .top) {
                                    Text(entry.preview).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                                }
                                .padding(8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("点击重新复制")
                            Divider()
                        }
                    }
                }
                // MenuBarExtra probes the minimum size; a maximum alone lets the list collapse.
                .frame(minHeight: 180, idealHeight: 280, maxHeight: 320)
            }
            Text(store.retention == .session ? "历史仅本次运行保留" : "历史保存在本机，重启后保留")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("清空历史", systemImage: "trash", action: store.clear)
                    .disabled((store.entries.isEmpty && store.storageError == nil) || store.isLoading)
                    .help("清空应用内历史，系统剪贴板内容保持不变")
                Button(showsSettings ? "返回历史" : "设置") { showsSettings.toggle() }
                    .disabled(store.isLoading)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
