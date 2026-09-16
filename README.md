# 剪贴板历史（macOS）

Swift + SwiftUI 菜单栏应用，支持 macOS 14 及以上，不显示 Dock 图标。

- 自动记录文本，最新记录在前，相同文本再次复制时置顶。
- 点击历史记录重新复制，使用 ⌘V 粘贴。
- 一键清空应用历史和本机缓存，不改动当前系统剪贴板。
- 设置页可选择保留 10 / 25 / 50 / 100 / 200 条，默认 50 条。
- 设置页可选择「退出后清空」或「重启后保留」，默认退出后清空。

## 运行

打开 `ClipboardHistory.xcodeproj`，选择 `ClipboardHistory` scheme，运行到 My Mac。也可以执行：

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory \
  -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
open build/Build/Products/Debug/ClipboardHistory.app
```

菜单栏点击剪贴板图标即可使用。首次复制时，如系统询问剪贴板访问权限，请根据需要允许。

工程已提交到工作目录，不需要安装第三方运行依赖。只有修改 `project.yml` 后才需要运行 `xcodegen generate` 重新生成工程。

## 测试

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory \
  -derivedDataPath build -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

测试仅使用独立剪贴板、模拟文本、独立偏好设置和临时目录。Debug 构建可传入 `--isolated-ui-check` 启动独立的界面验证实例；此时不会操作系统剪贴板，示例文本只用于检查界面。

详细实现与验证状态见 [开发文档](docs/development.md) 和 [架构说明](docs/architecture.md)。
