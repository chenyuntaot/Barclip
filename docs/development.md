# 一期：菜单栏文本与图片剪贴板历史

应用显示名称为 **Barclip**。工程 target 和 Swift 模块仍使用 `ClipboardHistory`。持久化历史写在 `~/Library/Application Support/Barclip/`；首次读取可从当前应用包内缓存或旧 `ClipboardHistory` 用户目录复制迁移，旧来源保留且不再写入。

## 实现状态（2026-09-18）

版权持有人显示为 **Yuntao Chen**（`© 2026 Yuntao Chen`）。关于页开发者姓名仍为陈云涛。文件中转站已接入：侧栏「文件」、两列图标网格、引用存储、面板内拖入、拖出复制、丢失态、空格预览、双击打开，以及拖文件时从菜单栏图标展开的气泡。进出设置使用固定面板尺寸，避免菜单栏窗口缩放后边缘残影。Debug XCTest 含稳定尺寸断言；真实访达拖到菜单栏气泡、三指拖移、空格预览以及点设置再返回的目视仍待重新启动应用后手动验收。

## 2026-09-18：版权姓名改为 Yuntao Chen

- Info.plist 版权、`AppInfo` 回退文案、设置/关于页展示、README 版权行改为 `© 2026 Yuntao Chen`。
- 开发者字段仍为「陈云涛」，不随界面语言翻译。
- 涉及：`project.yml`、`project.pbxproj`、`AppInfo.swift`、`ViewRenderingTests.swift`、README、开发与架构文档。
- 测试：Debug XCTest 52 项通过、0 失败；`testAppInfoExposesAboutMetadata` 断言版权为 `© 2026 Yuntao Chen`，开发者仍为陈云涛。设置页 / 关于页真实菜单栏展示仍待重新启动应用后目视。

## 2026-09-17：进出设置后窗口边缘残影

- 现象：在文件或历史页点击设置再返回，菜单栏窗口边缘出现黑边、玻璃拖影，侧栏按钮上还会留下「设置」提示。
- 根因：进出设置时侧栏收起/展开会改变窗口宽高，再叠加滑出过渡和整栏 `GlassEffectContainer`，液态玻璃会画到窗口外；弹簧动画还有轻微过冲。按钮上的 `.help` 与可见标题重复，返回后面板边缘会再弹出系统提示框。
- 修复：历史、文件、设置、关于共用固定面板尺寸；过渡改为短时透明度并裁剪在窗口内；选中态玻璃仍贴在单个按钮上。去掉与按钮标题重复的 `.help`。
- 涉及：`ClipboardMenuView.swift`、`ClipboardSettingsView.swift`、`ClipboardAboutView.swift`、`FileStagingView.swift`、`ViewRenderingTests.swift`、架构文档。
- 测试：Debug XCTest 52 项通过、0 失败；新增 `testMenuKeepsStableSizeWhenOpeningSettings`，断言历史、文件、设置、关于四页 `sizeThatFits` 宽高一致。真实菜单栏点设置再返回仍需退出旧进程后用新构建目视。

## 2026-09-17：文件中转站

- 功能：左侧增加「文件」。拖入只记录书签/路径，不复制文件字节，原位置保留；拖出用 `NSItemProvider.registerFileRepresentation(..., isInPlace: false)` 生成副本。文件页为两列网格，图标在上、名称在下。单击立即选中（不用 SwiftUI 双击手势，避免第一下被拖出手势吃掉）；空格打开独立预览窗口（图片走 ImageIO，其他走 Quick Look），预览期间保持安全范围访问；双击用默认应用打开。原文件删除后显示「文件已丢失」，清空暂存只删引用。
- 拖文件时：监听鼠标拖动，且仅当 `NSPasteboard.Name.drag` 的 changeCount 相对上次会话增加并带有文件 URL 时才弹出非激活 `NSPanel`。普通点击、按住鼠标或剪贴板上残留的旧文件引用不会打开暂存条。不打开 `MenuBarExtra`，也不激活应用。气泡从 Barclip 菜单栏图标下方展开；找不到图标时落在当前屏幕右上靠近菜单栏处，不居中。
- 存储：`file-staging.json` 与历史共用容量和保存策略，写在同一 Application Support/Barclip 目录。会话模式不写盘。
- 涉及：`FileStagingItem`、`FileStagingStore`、`FileStagingRepository`、`FileStagingTransfer`、`FileThumbnail`、`DragSessionMonitor`、`MenuBarDropAnchor`、`DropShelfController`、`FileQuickLookController`、`FileStagingView`、`DropShelfView`、`ClipboardMenuView`、`ClipboardHistoryApp`、本地化与测试。
- 技术选择：不把文件塞进 `ClipboardEntry`；不使用辅助功能或私有 API 打开 Extra。拖出强制非 in-place，避免访达同盘移动原件。
- 测试：覆盖引用存储、去重、丢失、复制不剪切、容量、持久化、损坏文件保留、拖放 URL 解析、点击/残留剪贴板不弹出、仅新的文件拖动才弹出、暂存条停在菜单栏图标/右上而非屏幕中央、图片缩略图与预览、非激活面板。
- 未做：Finder ⌘C 的文件不会进入暂存；临时文件失效后不自动拷贝；真实菜单栏里从桌面拖入暂存条、三指拖移、空格预览未在本机交互验收。

## 实现状态（2026-09-16）

代码实现完成，Xcode Debug / Release Build 与 33 项测试通过；真实菜单栏点击验收仍待手动完成，不能视为全量验收完成。

需求范围：macOS 原生、菜单栏常驻、Dock 不展示、文本与图片历史、左侧分类导航、一键清空当前分类、容量设置、设置页中的两种保存策略、设置页底部的程序版本 / 关于我们 / 版权，以及简体中文 / 英文界面（跟随系统语言）。

## 功能行为

| 功能 | 当前行为 |
| --- | --- |
| 分类导航 | 面板左侧上方纵向切换「文本」「图片」和「文件」。文本与图片是剪贴板历史；文件是独立暂存。左下角为清空、设置、退出，中间用横线分开 |
| 历史采集 | 启动后每 500ms 检查新复制内容，不导入启动前的当前剪贴板 |
| 类型判定 | 有 PNG / TIFF / JPEG 位图时记入图片（允许同时带 fileURL）；否则记入文本。同一份内容若同时有图和文字，只记图片。仅有文件引用、无位图时跳过 |
| 文件暂存 | 拖入只记 bookmark，原件不动。可从面板或拖文件时出现的菜单栏气泡放入。文件页两列图标网格。拖出复制、空格预览、双击打开。原件删除后标记丢失。Finder 复制的纯文件仍不进入文本/图片历史 |
| 排序与去重 | 新记录置顶；相同文本或相同 PNG 再次复制时移到顶部；同一文件再拖入暂存时置顶 |
| 文本保真 | 保留原始空格、换行和 Unicode；空白文本忽略 |
| 点击记录 | 写回系统剪贴板，显示已复制提示，由用户在目标应用粘贴 |
| 清空 | 文本/图片只清空当前分类的应用内历史；文件页清空暂存引用且不删除原文件。都不改系统剪贴板 |
| 容量 | 10、25、50、100、200，默认 50；文本、图片和文件各自保留该数量，调小立即移除最旧记录 |
| 退出后清空 | 默认模式，仅在当前进程保留；切换到此模式立即删除磁盘缓存 |
| 重启后保留 | 将当前及后续历史写进用户 Application Support/Barclip，启动时恢复；删除应用后仍保留 |
| 设置 | 进入后侧栏收起，左右合为一块，左上角返回；面板外框尺寸与历史/文件页相同，避免菜单栏窗口缩放。设置选择跨重启保留，并展示带复制按钮的实际磁盘缓存目录。底部显示程序版本、关于我们和版权，点击进入关于页 |
| 关于 | 显示程序版本、开发者陈云涛、联系邮箱、项目仓库和版权 © 2026 Yuntao Chen。邮箱和仓库用系统默认应用打开。返回回到设置 |
| 语言 | 简体中文和英文，跟随系统语言；无应用内语言开关。Barclip、开发者姓名陈云涛、邮箱、仓库和版权姓名 Yuntao Chen 不翻译 |
| 退出 | 停止监听并等待最新缓存操作；失败时可返回重试 |

实现文件和技术选择见 [architecture.md](architecture.md)。

## 已执行验证

在当前 Mac、Xcode 27 / Swift 6.4 上执行：

- Xcode Debug / Release Build：通过，Swift 6 编译和类型检查通过。当前为 51 项 XCTest，含文件暂存。
- XCTest：33 项通过，无失败；涵盖文本排序、去重、空白保真、容量、清空后不回填、重复操作、非文本与超大文本、图片排序去重、图文独立容量、图片复制失败、访问拒绝、读取重试、复制失败、监控停止/重启、截图样式 TIFF/PNG+fileURL 收录与纯文件跳过、关于页元数据、设置页底部入口高度与应用图标配置。
- 本机 NSPasteboard 集成：使用 withUniqueName 创建的隔离剪贴板，验证读写、多行 Unicode、PNG 读写、TIFF 转 PNG、图文并存、图片/文件/敏感标记过滤、位图与 fileURL 并存时仍收录图片。
- 持久化：重建 Store 模拟重启恢复、清空落盘、策略切换、容量落盘、密集写入后清空、旧版本写入拒绝、损坏文件保留、写入失败与重试恢复、用户 Application Support 路径、删除应用后新缓存保留、旧包内和 Application Support 缓存复制迁移、清空后不再导入、迁移失败重试、图片 sidecar 恢复、缺失图片文件时跳过该条。
- 原生视图渲染：空状态、文本历史、图片空状态、图片列表、设置页、整页设置布局、关于页，包含浅色/深色，生成快照供布局检查。
- 测试宿主实际激活策略断言 `.accessory` 通过；构建产物 Info.plist 的 `LSUIElement` 为 true。
- 隔离界面实例启动成功，但电脑控制工具连接这个无主窗口应用时超时，因此未将实际菜单栏交互或 Dock 目视检查标记为通过。

测试目录：`ClipboardHistoryTests`。测试不读取用户真实剪贴板，不操作生产缓存。日志中预期的读写失败来自故障模拟。

## 待手动验收

1. 正常启动应用，检查菜单栏图标可见且 Dock 无图标。
2. 从文本编辑器复制中文、多行、Emoji，打开菜单验证内容；点击旧记录，在编辑器粘贴验证原文。
3. 用系统截图（⌘⇧3 / ⌘⇧4，或 ⌘⌃⇧3 / ⌘⌃⇧4 直接进剪贴板）后打开「图片」，确认缩略图出现；点击后在预览或文稿中粘贴。也可从预览复制图片验证。
4. 确认文本与图片历史互不影响；清空只清除当前分类。
5. 关闭面板后继续复制，重新打开确认监听仍在工作。
6. 设置容量 10 条，复制超过 10 条不同文本和图片，确认各类只保留最新 10 条。
7. 选择重启后保留，退出并重新打开，确认文本、图片和设置恢复。
8. 切换退出后清空，确认当前记录仍可用，退出重开后为空。
9. 清空后关闭再打开面板，确认历史不回填；重复清空、返回设置正常。
10. 在支持剪贴板访问控制的系统上拒绝/恢复权限，验证提示和恢复。
11. 检查真实浅色/深色环境、小屏幕、键盘导航和 VoiceOver。
12. 打开设置，确认显示当前用户的完整磁盘缓存目录且可点击按钮复制；在 Finder 的“前往文件夹”中粘贴后能进入该目录。确认底部显示程序版本、关于我们和版权；点击进入关于页后返回设置，再返回历史。点击邮箱和仓库能打开对应应用。
13. 在 Finder 中查看 `Barclip.app` 图标是否为彩色剪贴板 AppIcon；关于页顶部显示同一应用图标。菜单栏 Extra 和历史面板左上角应为模板剪贴板线稿，随浅色/深色界面变色。
14. 将系统语言改为 English，确认面板、设置、关于页和退出确认框为英文；Barclip、开发者陈云涛、版权 Yuntao Chen、邮箱和仓库保持原样。改回简体中文后界面恢复中文。
15. 从桌面或访达拖一个文件：菜单栏附近出现「拖到此处暂存」，松手后原件仍在，打开「文件」能看到该条。三指拖移同样验证。
16. 在「文件」中把暂存项拖到桌面另一位置，确认得到副本且原件未移动；空格预览、双击打开；删除原件后该条显示丢失；清空暂存不删除原件。

## 已知限制与后续方向

- 500ms 内连续复制可能丢失中间值。
- 图片仅收录剪贴板中的 PNG / TIFF / JPEG 位图；GIF、PDF、HEIC 不收录。有位图时即使同时带 fileURL 也会收录（系统截图常见）。仅有文件引用、无位图的 Finder 复制仍跳过。同一份剪贴板同时有图和文字时只记图片。
- 文件暂存只保存位置，不把文件字节写入缓存。邮件或浏览器里的临时文件稍后可能显示丢失。拖出依赖目标应用遵守非 in-place 复制；极端情况下个别应用仍可能忽略该标记。
- 单条文本上限 1 MiB，单条图片上限 30 MiB；不包含搜索、收藏、全局快捷键、开机启动、云同步和自动粘贴。
- 持久化为用户 Application Support/Barclip 中的 JSON 和图片，未加密；删除或替换 `Barclip.app` 不会清掉新目录中的历史。强制结束进程或断电可能丢失尚未写入的最新变更。
- 容量和保存策略仍在 UserDefaults（`~/Library/Preferences/local.ClipboardHistory.plist`），删除应用后这项设置可能残留，但不含剪贴板内容。
- 用户数据目录不可写时，「重启后保留」会保存失败；应用包不再写入历史。旧版来源保留在原位置，清空只处理新目录，迁移标记防止重新导入。
- 已验证当前 Mac；macOS 14/15 的真实系统权限与界面行为仍需对应系统验收。
- 当前构建用于本机开发，未进行 Developer ID 分发签名或公证；已制作本地 DMG。
- 关于页中的邮箱和仓库链接会打开系统默认应用，菜单栏面板可能会因此关闭。
- 如后续扩展媒体、大数据量、索引或更高频采集，应单独评估存储和监听方案。

## 构建产物

本机 Release 应用：`build/Build/Products/Release/Barclip.app`。最终工程统一使用自动生成的 Info.plist，已删除合并过程中遗留的重复文件。应用图标来自仓库根目录 `AppIcon.icon`。

## 2026-09-16：接入 Icon Composer 应用图标

- 将用户添加的 `AppIcon.icon` 加入 ClipboardHistory 的 Resources，并设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- Finder / Get Info / 关于页使用该图标。
- `project.yml` 将 `.icon` 按文件收录，避免 xcodegen 把包内 json/png 拆开复制。
- 测试断言构建产物 `CFBundleIconName` 为 `AppIcon`。菜单栏与 Finder 目视仍待手动验收。

## 2026-09-16：菜单栏改为模板剪贴板线稿

- 用户提供的白底剪贴板线稿做成 macOS 状态栏 / MenuBarExtra 模板图。本项目只面向 macOS，没有 iOS target；这是对应的状态栏图标。
- 处理：黑场变透明、裁切留白、放入 22pt / 44px 画布，资源渲染意图为 Template。
- Finder 和关于页仍用彩色 `AppIcon.icon`。
- 测试断言 `MenuBarIcon` 可加载且 `isTemplate`，并渲染浅色/深色快照。真实菜单栏观感仍待手动验收。
- 历史面板左上角标题由系统 `clipboard` 符号改为同一套 `ClipboardGlyph` 模板图。

## 2026-09-16：GitHub 风格 README

- 根目录 `README.md` 改为带应用图标的 GitHub 风格介绍页，图标和面板截图放在 `docs/images/`。
- 实现细节、测试结果和已知问题仍以 [development.md](development.md) 与 [architecture.md](architecture.md) 为准。

## 2026-09-16：菜单栏 Extra 改用 AppIcon

- 从编译后的 `AppIcon.icns` 导出 22pt / 44px 原色位图 `MenuBarIcon`，渲染意图为 Original，避免 MenuBarExtra 把它当成模板剪影。
- `ClipboardHistoryApp` 的 Extra 标签改为这张图，不再使用系统 `clipboard` 符号。
- 测试加载 `MenuBarIcon` 资源并渲染浅色/深色快照。真实菜单栏观感仍待手动验收。

## 2026-09-16：设置页程序版本和关于我们

- 设置页最下方显示程序版本、关于我们和版权；整块可点击，进入同一面板中的关于页，不另开窗口。
- 关于页展示 Barclip 版本、开发者陈云涛、联系邮箱 `chenyuntao0123@icloud.com`、项目仓库 `https://github.com/chenyuntaot/Barclip` 和版权 `© 2026 Yuntao Chen`。邮箱与仓库用系统默认应用打开。
- 版本号来自 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（当前 1.0.1 / 2），版权写入生成的 Info.plist。
- 关于页复用设置页的本地切换和返回按钮；未使用 NavigationStack，避免和侧栏收起动画冲突。
- 测试覆盖关于页元数据、设置页底部高度，以及设置页 / 关于页浅色与深色渲染快照。菜单栏点击仍待手动验收。

## 2026-09-16：系统截图收录

- 图片判定不再因 `fileURL` 整体拒绝。存在 PNG / TIFF / JPEG 位图即写入图片历史，覆盖系统截图保存到桌面后再复制、以及部分带预览位图的图片文件复制。
- 仅有文件引用、没有位图的剪贴板仍跳过；文本判定仍拒绝 `fileURL`，避免把路径当文本。
- 单条图片上限从 8 MiB 提高到 30 MiB，降低 Retina 全屏截图被跳过的概率。
- 未接入 ScreenCaptureKit，也不监听桌面文件夹；只消费系统剪贴板里已经出现的位图。
- 测试覆盖：隔离剪贴板上 PNG+fileURL、TIFF+fileURL 判定为图片；纯 fileURL 仍跳过；Store 轮询能把截图样式的 TIFF+fileURL 写入图片历史。26 项测试通过。

## 2026-09-16：设置页收起侧栏

- 点击设置后左侧按钮全部消失，分隔线收起，内容区铺满。
- 仅在左上角显示返回。进出设置最初用弹簧滑出；后改为固定窗口尺寸加透明度过渡，避免菜单栏液态玻璃边缘残影。

## 2026-09-16：侧栏悬停与 Liquid Glass 选中

- 选中为强调色文字加液态玻璃，玻璃不出现在悬停上。
- 悬停只做轻微放大和字色略深；清空、设置、退出同样有悬停反馈。
- 更早系统的选中态回退为薄材料。

## 2026-09-16：清空、设置、退出移到左侧栏底部

- 「清空历史」「设置」「退出」放到左侧栏左下角，与「文本」「图片」之间用横线分隔。
- 右侧内容区不再放这三项操作。

## 2026-09-16：侧栏选中居中，底栏操作左对齐

- 分类按钮改用自定义 ButtonStyle，选中背景在侧栏内水平居中，避免 macOS 默认 Button 边距把高亮挤到右边。
- 「清空历史」「设置」「退出」全部靠左排列。

## 2026-09-16：文本/图片分类导航

- 面板左侧增加纵向「文本」「图片」导航，分类选择留在 View 本地状态。
- 图片历史与文本历史分开保存和计数，容量对两类各自生效；清空只清当前分类。
- PNG / TIFF / JPEG 位图写入图片历史，TIFF/JPEG 转成 PNG 存储；与文字同时存在时只记图片。仅文件引用、无位图的 Finder 复制仍跳过。
- 持久化 JSON 只存元数据，图片写在同目录 `images/{id}.png`；缺失 sidecar 时跳过该条，不中断整份历史。
- 全部 25 项测试通过。

## 2026-09-16：历史缓存改为随应用包删除（历史方案，已被用户目录方案替代）

- 正式存储从 `~/Library/Application Support/ClipboardHistory/` 改为 `Barclip.app/Contents/Library/Application Support/history.json`。
- 删除应用包即删除历史；启动时若发现旧目录会迁入新位置并删除旧文件。
- 测试覆盖包内路径、删除应用包后文件消失、旧缓存迁移、清空时删除旧目录。
- 全部 20 项测试通过。未改 UserDefaults 中的容量和保存策略。

## 2026-09-16：应用显示名称改为 Barclip

- 菜单栏标题、面板标题和 `CFBundleDisplayName` 改为 Barclip；构建产物为 `Barclip.app`。
- 未改 Swift 模块名、Bundle ID 和 `~/Library/Application Support/ClipboardHistory/`，已保存的历史与测试导入保持不变。

## 2026-09-16：修复有数量但看不到历史记录

- 用户截图显示计数为 3，列表区域却被压扁。
- 根因：ScrollView 仅设置 `maxHeight: 320`，MenuBarExtra 探测最小布局尺寸时允许其高度塌缩；LazyVStack 中的记录没有获得可见空间。
- 修改：为列表设置 180 点最小高度、280 点理想高度、320 点最大高度；仍然支持滚动，不改动历史数据和采集逻辑。
- 回归：新增 `testHistoryRemainsVisibleUnderCompactMenuProposal`，使用真实 ClipboardMenuView 和 3 条模拟数据，在 NSHostingController 最小高度提议下测量。修复前面板只有 151.08 点，断言失败；修复后通过。额外渲染该紧凑布局，检查三条记录可见。
- 全部 16 项测试通过。原先只验证理想尺寸的快照，未覆盖菜单栏最小尺寸协商，这是之前漏检的原因。
- 真正运行中的旧应用不会热更新，需退出后重新打开新构建。会话模式退出会清空历史；需要保留时可先在设置选择“重启后保留”。

## 2026-09-16：1.0.1 DMG 构建

- 版本：1.0.1，构建号 2；同步 `project.yml`、Xcode 工程和 README 版本标识，保留当前工作区功能变更。
- 产物：`build/Barclip-1.0.1.dmg`（约 3.6 MB），内含 `Barclip.app` 和指向 `/Applications` 的拖拽安装入口。
- 从独立的 `build/release-1.0.1/DerivedData` 构建 Release，架构为 arm64 + x86_64，最低 macOS 14。镜像只使用本次新构建，不含用户历史或测试包。
- 打包使用系统 `hdiutil` 的 UDZO 压缩格式，应用采用 ad-hoc 本地签名；没有 Developer ID 签名或 Apple 公证。
- 验证：Release Build 通过；Debug XCTest 30 项通过、0 失败；镜像校验、只读挂载、包内版本 1.0.1 (2)、双架构、Applications 链接和签名完整性检查通过。验证后已卸载镜像。
- 日志：`build/release-1.0.1/build.log`、`build/release-1.0.1/test.log`。
- SHA-256：`20bfffc9980af723e96ce2c17d9192d9c01ceb15ab873dbdfc57e8ed5feaf97e`。
- 安装时先将应用拖入 Applications 再运行；DMG 是只读的，不适合直接运行并保存历史。本次未覆盖现有安装，未执行真实剪贴板或 Intel 实机交互验收。
- 后续公开分发需评估 Developer ID 签名、公证及包内历史存储对签名的影响，现有手动验收项仍保留。

## 2026-09-16：历史迁移到用户 Application Support

- 实现：`HistoryRepository` 默认保存到 `~/Library/Application Support/Barclip/history.json`，图片在同级 `images/`；不再写入或删除应用包内容。
- 迁移：新缓存优先，否则按当前应用包、旧 ClipboardHistory 用户目录的顺序复制文本和图片。来源保留；迁移标记避免清空或会话模式重启后回填。失败保留来源并通过现有 Store 错误及重试流程处理。
- 涉及：`HistoryRepository.swift`、`HistoryPersistenceTests.swift`、`ClipboardSettingsView.swift`、`Localizable.xcstrings`、README 和架构文档。中文和英文设置说明同步更新。
- 技术决策：用户目录允许在不修改签名包的情况下持久化；不自动删除旧来源。卸载不再自动删除历史，旧包被替换前未迁移的缓存无法恢复；手动删除新数据目录也会删除迁移标记。
- 测试：Debug XCTest 33 项通过，0 失败；Release arm64 + x86_64 构建通过，Swift 编译和类型检查通过。覆盖新路径、文本/图片迁移、删除旧应用后新数据保留、新缓存优先、清空不回填、源数据损坏及目标写入失败后的重试。所有迁移测试使用临时目录和模拟数据，不操作真实历史；真实旧安装升级和菜单栏交互未手动验收。日志为 `build/storage-migration-test.log` 和 `build/storage-migration-release.log`。
- 本次修改源码，之前生成的 `build/Barclip-1.0.1.dmg` 仍是修改前版本。签名、公证和更新 DMG 需后续另行执行。

## 2026-09-17：设置页展示磁盘缓存目录

- 设置页新增“磁盘缓存”区域，展示当前用户实际使用的完整目录路径，文本可选中复制，便于在 Finder 的“前往文件夹”中打开并手动清理。
- 展示路径与持久化路径共用 `HistoryRepository.cacheDirectoryURL`，不在界面中重复硬编码。
- 缓存加载中或读取失败时只禁用容量与保存策略控件，目录路径和关于入口仍可操作，确保缓存损坏时也能复制地址进行人工处理。
- 涉及：`HistoryRepository.swift`、`ClipboardSettingsView.swift`、`Localizable.xcstrings`、持久化与本地化测试、开发及架构文档。
- 测试：Debug XCTest 33 项通过、0 失败，Release arm64 + x86_64 Build 通过；覆盖缓存目录和历史文件路径一致性、新增英文文案，以及设置页中英文和浅色/深色渲染。已检查 360pt 宽中文快照，完整路径换行正常且底部关于入口可见；Finder 复制粘贴仍待手动验收。

## 2026-09-17：文件选中、气泡与底部说明

- 拖入气泡悬停时保持不透明窗口底色，只加强描边和字色，不再用半透明填充。窗口本身透明、无矩形阴影，只露出气泡外形。
- 气泡内展示盒子图标、Barclip 名称和「拖到此处暂存」。
- 去掉「历史写在应用内…」一类页脚；文件页底部改为「暂存区只记录文件引用。」
- 文件选中改为侧栏同款液态玻璃贴在图标周围（macOS 26 `glassEffect`），文件名用强调色，不再给整格铺底。

## 2026-09-17：文件页网格、预览与菜单栏气泡
- 空格预览改为应用内浮动窗口：预览期间保持 bookmark 安全范围访问；能解码的图片用 ImageIO/`NSImage` 显示，其他类型再用 `QLPreviewView`。不再依赖 `QLPreviewPanel` 从菜单栏 Extra 弹出。
- 「拖到此处暂存」改为带箭头的气泡，定位在 Barclip 菜单栏图标下方并从箭头处放大展开；找不到图标时落在屏幕右上菜单栏附近，不再居中。
- 涉及：`FileStagingView.swift`、`FileThumbnail.swift`、`FileQuickLookController.swift`、`DropShelfView.swift`、`DropShelfController.swift`、`MenuBarDropAnchor.swift`、`FileStagingItem.swift`、本地化与测试。
- 验证：Debug XCTest 51 项通过、0 失败。覆盖两列网格渲染、图片缩略图/预览、气泡不居中。真实菜单栏拖入、空格预览和点击选中仍需退出后重新打开新构建的 `Barclip.app` 再确认。

## 2026-09-17：设置说明浮窗与地址复制

- 实现：历史容量、保存策略、磁盘缓存的说明默认隐藏，在分区标题右侧添加圆形 i 按钮；点击展示原生 popover，外部点击由系统关闭。说明保留中英文。
- 文件夹地址右侧添加复制按钮，取消文本选中；显示成功或失败提示，失败后可重试。复用 Store 的剪贴板服务并同步 changeCount，避免把设置路径自动加入历史。加载或缓存读取失败时复制按钮仍可操作。
- 涉及：`ClipboardSettingsView.swift`、`ClipboardStore.swift`、`Localizable.xcstrings`、`ClipboardStoreTests.swift`、架构文档。
- 技术选择：共用局部状态的分区标题组件与 SwiftUI 原生浮窗，不增加全局监听或依赖；后续设置说明可复用此组件。
- 验证：Debug 构建与 34 项 XCTest 通过（0 失败），Release 构建通过；新增测试覆盖地址复制失败、重试、重复复制和不自动收录历史。既有渲染测试覆盖中英文、浅色/深色，已目视检查 360pt 中文快照中的 i 按钮、路径换行和复制按钮。既有测试 teardown 的 actor 隔离警告仍存在。真实 MenuBarExtra 中逐项点击 i、外部关闭、重复打开、返回，以及复制后在 Finder 粘贴仍待手动验收。
