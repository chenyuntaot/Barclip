import AppKit
import SwiftUI

struct ClipboardMenuView: View {
    @Environment(ClipboardStore.self) private var store
    @Environment(FileStagingStore.self) private var files
    @State private var showsSettings = false
    @State private var showsAbout = false
    @State private var selectedSection: SidebarSection

    init(
        initialKind: ClipboardKind = .text,
        isShowingSettings: Bool = false,
        isShowingAbout: Bool = false,
        showsFiles: Bool = false
    ) {
        if showsFiles {
            _selectedSection = State(initialValue: .files)
        } else {
            _selectedSection = State(initialValue: initialKind == .image ? .image : .text)
        }
        _showsSettings = State(initialValue: isShowingSettings || isShowingAbout)
        _showsAbout = State(initialValue: isShowingAbout)
    }

    private var isAccessoryPanel: Bool {
        showsSettings || showsAbout
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !isAccessoryPanel {
                kindRail
                    .frame(width: 64)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                Divider()
                    .transition(.opacity)
            }
            Group {
                if showsAbout {
                    aboutColumn
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 18)),
                            removal: .opacity.combined(with: .offset(x: 18))
                        ))
                } else if showsSettings {
                    settingsColumn
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 18)),
                            removal: .opacity.combined(with: .offset(x: 18))
                        ))
                } else if selectedSection == .files {
                    FileStagingView()
                        .padding(.leading, 12)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -10)),
                            removal: .opacity.combined(with: .offset(x: -10))
                        ))
                } else {
                    mainColumn
                        .padding(.leading, 12)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -10)),
                            removal: .opacity.combined(with: .offset(x: -10))
                        ))
                }
            }
            .frame(width: isAccessoryPanel ? 436 : 360)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .onAppear { MenuBarDropAnchor.rememberOpenExtra() }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsSettings)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsAbout)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedSection)
    }

    private var currentKind: ClipboardKind {
        selectedSection.clipboardKind ?? .text
    }

    private var currentEntries: [ClipboardEntry] {
        store.entries(for: currentKind)
    }

    @ViewBuilder
    private var kindRail: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { railButtons }
        } else {
            railButtons
        }
    }

    private var railButtons: some View {
        VStack(spacing: 8) {
            ForEach(SidebarSection.allCases) { section in
                railButton(
                    title: LocalizedStringKey(section.titleKey),
                    systemImage: section.systemImage,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                    closeAccessoryPanels()
                    if section == .files { files.refresh() }
                }
                .help(LocalizedStringKey(section.titleKey))
                .accessibilityLabel(LocalizedStringKey(section.titleKey))
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
            Spacer(minLength: 12)
            Divider()
            railButton(
                title: selectedSection == .files ? "清空暂存" : "清空历史",
                systemImage: "trash",
                disabled: selectedSection == .files ? files.isLoading : store.isLoading
            ) {
                if selectedSection == .files {
                    files.clear()
                } else {
                    store.clear(currentKind)
                }
            }
            .help(
                selectedSection == .files
                    ? "清空暂存的文件引用，不会删除原文件"
                    : "清空当前分类的应用内历史，系统剪贴板内容保持不变"
            )
            .accessibilityLabel(selectedSection == .files ? "清空暂存" : "清空历史")
            railButton(
                title: "设置",
                systemImage: "gearshape",
                disabled: store.isLoading
            ) {
                showsAbout = false
                showsSettings = true
            }
            .help("设置")
            .accessibilityLabel("设置")
            railButton(title: "退出", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .help("退出")
            .accessibilityLabel("退出")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func railButton(
        title: LocalizedStringKey,
        systemImage: String,
        isSelected: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(KindRailButtonStyle(isSelected: isSelected))
        .disabled(disabled)
    }

    private var settingsColumn: some View {
        accessoryColumn(backHelp: String(localized: "返回历史"), backDisabled: store.isLoading) {
            closeAccessoryPanels()
        } content: {
            ClipboardSettingsView(onOpenAbout: { showsAbout = true })
        }
    }

    private var aboutColumn: some View {
        accessoryColumn(backHelp: String(localized: "返回设置")) {
            showsAbout = false
        } content: {
            ClipboardAboutView()
        }
    }

    private func accessoryColumn<Content: View>(
        backHelp: String,
        backDisabled: Bool = false,
        backAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: backAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text("返回")
                    }
                }
                .buttonStyle(SettingsBackButtonStyle())
                .help(backHelp)
                .accessibilityLabel(backHelp)
                .disabled(backDisabled)
                Spacer(minLength: 0)
            }
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private func closeAccessoryPanels() {
        showsAbout = false
        showsSettings = false
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("Barclip")
                } icon: {
                    ClipboardGlyph(pointSize: 16)
                }
                .font(.headline)
                .labelStyle(.titleAndIcon)
                Spacer()
                Text("\(currentEntries.count) / \(store.capacity)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            if store.accessDenied {
                Label("剪贴板访问被拒绝，请在系统设置中允许此应用读取剪贴板。", systemImage: "lock")
                    .font(.callout)
                Button("重新检查", action: store.retry)
            } else if let message = store.message {
                Text(message.text).font(.caption).foregroundStyle(.secondary)
                if message.allowsRetry {
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
            if store.isLoading {
                ProgressView("正在读取历史…").frame(maxWidth: .infinity).frame(height: 220)
            } else if currentEntries.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: currentKind == .text ? "doc.on.clipboard" : "photo")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("暂无历史记录").font(.headline)
            Text(currentKind == .text ? "复制一段文本后，它会出现在这里。" : "复制一张图片后，它会出现在这里。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(currentEntries) { entry in
                    Button { store.copy(entry) } label: {
                        HStack(alignment: .top) {
                            rowContent(for: entry)
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

    @ViewBuilder
    private func rowContent(for entry: ClipboardEntry) -> some View {
        if entry.kind == .image {
            imagePreview(entry.imagePNG)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.preview).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func imagePreview(_ data: Data?) -> some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Label("无法预览图片", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KindRailButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        KindRailButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct KindRailButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var isSelected: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .multilineTextAlignment(.center)
            .frame(width: 52, alignment: .center)
            .padding(.vertical, 10)
            .foregroundStyle(labelColor)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(RailGlassEffect(isActive: isSelected))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(hoverScale)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .animation(.easeInOut(duration: 0.12), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovered = $0 && isEnabled }
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var labelColor: Color {
        if isSelected { .accentColor }
        else if isHovered && isEnabled { .primary }
        else { .secondary }
    }

    private var hoverScale: CGFloat {
        if configuration.isPressed { 0.97 }
        else if isHovered && isEnabled { 1.06 }
        else { 1 }
    }
}

private struct SettingsBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsBackButtonBody(configuration: configuration)
    }
}

private struct SettingsBackButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered && isEnabled ? 1.06 : 1))
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
    }
}

struct RailGlassEffect: ViewModifier {
    var isActive: Bool
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return glassBody(content: content, shape: shape)
    }

    @ViewBuilder
    private func glassBody(content: Content, shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(isActive ? .regular : .identity, in: shape)
        } else if isActive {
            content.background { shape.fill(.ultraThinMaterial) }
        } else {
            content
        }
    }
}
