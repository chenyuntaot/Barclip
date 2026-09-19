# 架构与技术决策

## 平台与入口

原生 Swift 6 + SwiftUI，最低 macOS 14（Observation）。不引入第三方运行依赖。
`ClipboardHistoryApp` 只创建 `MenuBarExtra` 作为主面板，并另建一个预创建的非激活 `NSPanel` 作为拖文件时的暂存条，不创建 Dock 主窗口。生成的 Info.plist 设置 `LSUIElement = YES`、`CFBundleDisplayName = Barclip`，AppDelegate 同时设置 `.accessory` 激活策略。产物名称为 `Barclip.app`，Swift 模块名仍为 `ClipboardHistory`。应用图标使用仓库根目录的 Icon Composer 文件 `AppIcon.icon`，由 asset catalog 编译进应用包。菜单栏 Extra 和使用页左上角标题都使用用户提供的剪贴板线稿做成的模板图 `MenuBarIcon`。黑底转为透明，由系统按浅色/深色界面着色，不使用彩色 AppIcon 或系统 `clipboard` 符号。

使用菜单栏弹出面板中的设置页，避免为设置项引入独立窗口。`ClipboardMenuView` 本地管理分类、设置页与关于页切换，Store 通过 Environment 注入。进入设置或关于页时侧栏与分隔线收起，左右合为一块，仅左上角保留返回。历史、文件、设置和关于共用固定面板尺寸，过渡只用短时透明度并裁剪在窗口内，避免菜单栏窗口缩放后液态玻璃在边缘留下残影。关于页不另开窗口，也不在 MenuBarExtra 中使用 NavigationStack，以免和现有返回按钮冲突。侧栏选中态为强调色文字加 Liquid Glass（仅选中项）；悬停只放大并略加深字色。

开机启动使用 `ServiceManagement.SMAppService.mainApp`，直接把当前 `Barclip.app` 登记为登录项。最低系统为 macOS 14，因此不嵌入登录助手，也不使用已弃用的 `SMLoginItemSetEnabled` 或自写 LaunchAgent。开关状态读取系统登录项，不在应用偏好里再存一份，避免用户在系统设置中关闭后应用内仍然显示已打开。需要用户批准时打开系统登录项面板；从 Xcode 或其他非正式位置运行时，系统可能返回 `notFound`，界面提示把应用放到应用程序文件夹。测试注入模拟服务，避免 XCTest 修改本机登录项。

文件暂存与剪贴板历史分开。拖入只保存 bookmark，不把文件字节写入 Application Support。从网格拖出时用 `NSFilePromiseProvider` 生成副本，避免访达把原件当成移动。拖文件时不尝试程序化打开 MenuBarExtra，只显示从菜单栏图标展开的非激活气泡；检测要求拖放剪贴板 changeCount 增加且指针已超过拖动阈值，不使用辅助功能，也不把普通点击当成拖动。

## 责任划分

- `Models/ClipboardEntry.swift`：文本/图片分类、原始文本或 PNG、预览和保存策略。
- `Models/AppInfo.swift`：显示名、版本、版权、开发者与仓库等关于页元数据。
- `Services/PasteboardService.swift`：AppKit 剪贴板读写、文本与位图筛选、访问拒绝判断。
- `Services/HistoryRepository.swift`：actor 隔离 JSON 元数据与图片 sidecar 读写。
- `Stores/ClipboardStore.swift`：Observation 状态、轮询、去重、容量裁剪、恢复与保存编排。状态提示用 `StatusMessage` 枚举，界面按 `allowsRetry` 决定是否显示重试，不再用中文字符串前缀判断。
- `Localizable.xcstrings`：简体中文为源语言，另含英文。界面随系统语言切换，应用内不提供语言选项。
- `Models/FileStagingItem.swift`：暂存项、书签刷新、侧栏分区。
- `Stores/FileStagingStore.swift`：拖入去重、容量、保存策略、丢失标记。
- `Services/FileStagingRepository.swift`：`file-staging.json` 读写。
- `Services/FileStagingTransfer.swift`：拖入 URL 解析、拖出文件 Promise 复制。
- `Services/DragSessionMonitor.swift`：拖放剪贴板与指针状态。
- `Services/MenuBarDropAnchor.swift`：暂存条定位，优先菜单栏图标，其次右上，不用屏幕中央。
- `Services/DropShelfController.swift`：非激活菜单栏气泡暂存条。
- `Services/FileThumbnail.swift`：图片 ImageIO 缩略图与预览位图。
- `Services/FileQuickLookController.swift`：独立预览窗口；图片走位图，其他走 Quick Look。
- `Views/FileStagingView.swift` / `DropShelfView.swift`：两列文件网格与菜单栏气泡。
- `Views/ClipboardMenuView.swift`：左侧分类、历史、复制、清空、状态提示、设置与关于入口。历史/文件/设置/关于共用固定面板尺寸，进出设置只做透明度过渡。
- `Stores/LaunchAtLoginStore.swift`：设置页开机启动开关的展示状态与错误提示，系统登录项是唯一事实来源。
- `Services/LaunchAtLoginService.swift`：`SMAppService.mainApp` 注册/注销当前应用，并打开系统登录项设置。需要批准、安装位置无法注册、用户取消或系统失败时由 Store 给出提示。
- `Views/ClipboardSettingsView.swift`：容量、保存策略、登录时打开、带复制按钮的实际缓存目录，以及底部程序版本 / 关于我们 / 版权入口。缓存目录直接读取 `HistoryRepository` 的路径定义，避免展示地址与实际存储位置不一致。复制地址复用 Store 注入的剪贴板服务，并更新 changeCount 防止路径被自动收录；成功或失败反馈放在设置 View 的局部状态。四个分区的说明收纳在标题右侧的 `info.circle` 按钮中，共用 `SettingsSectionHeader`；使用局部 `@State` 和原生 SwiftUI `.popover`，由系统处理外部点击关闭，不添加全局点击监听或第三方依赖。开机启动不写入 UserDefaults。
- `Views/ClipboardAboutView.swift`：程序版本和关于我们页面，展示编译后的应用图标。

## 监听方式

使用应用生命周期内的 Swift Concurrency Task，每 500ms 检查 NSPasteboard.changeCount，仅变更后读取。若剪贴板含 PNG / TIFF / JPEG 位图则记入图片历史（TIFF 与 JPEG 转成 PNG），即使同时带 `fileURL` 也收录，以便捕获系统截图。否则读取文本。菜单关闭后仍然工作，退出时取消。读前后校验 changeCount，避免读到跨版本内容。同一份内容同时有图和文字时只保留图片，避免把图片附带的 URL 记进文本历史。仅有 `fileURL`、没有位图时整份跳过。

没有使用私有通知或辅助功能注入。轮询成本低，但可能遗漏 500ms 内连续复制的中间值；如果后续要求完整捕获高频事件，需要重新评估此约束。

## 保存与错误恢复

默认只保存在内存；容量和保存策略通过 UserDefaults 保留。
持久化模式把 `history.json` 写在 `~/Library/Application Support/Barclip/`，图片二进制写在同级 `images/{id}.png`。目录权限 0700，文件权限 0600，JSON 原子写入；文件并未加密。全部处理在本机完成，无网络请求。删除或替换应用不会删除历史；切换为会话模式删除当前目录中的历史和图片。

JSON 只保存文本和图片文件名，避免把位图 base64 进同一份文件。旧版纯文本 JSON 仍可读取。缺失的图片 sidecar 会跳过该条，不让整份历史加载失败。读取图片始终相对当前正在解码的 JSON 所在目录，迁移时也能正确恢复图片。

为保持签名后的应用包不变，放弃原来的包内写入方案，采用用户 Application Support 目录。没有增加卸载助手。代价是卸载后仍留存用户历史，设置页明确说明此行为；签名、公证仍需单独配置。

新目录中的历史优先。首次读取新目录为空且无 `.migration-complete` 标记时，依次检查当前应用包的 `Contents/Library/Application Support/history.json` 和旧 `~/Library/Application Support/ClipboardHistory/history.json`，复制第一个存在的快照及其图片。成功后写入迁移标记；读取或写入失败向 Store 抛错，保留来源供重试。旧目录只读，不删除、不改写，避免修改签名包或丢失旧副本。若升级时已替换掉旧应用包，程序无法恢复已经被替换的包内历史。

保存新历史、清空、切换会话模式或首次空读取都会记录迁移已处理；清空时先写标记，再删除快照。标记不含历史内容且在清空后保留，防止重启后重新导入旧数据。旧副本仍留在原位置，需用户自行处理；如果手动删除整个 Barclip 数据目录，标记也会消失，下次可能重新导入仍存在的旧副本。

选择 JSON 是因为第一期记录上限为 200，无复杂查询需求；未引入数据库或 SwiftData。以后若引入搜索索引、大规模媒体或大量记录，再评估存储方案。

磁盘操作在 actor 上执行，不在主线程编码、读取和写入。每份快照带单调递增版本，晚到的旧版本不会恢复已清空的数据。清空与切换为会话模式删除历史文件。正常退出会等待最新写入；保存失败时允许返回重试或明确选择仍然退出。

缓存损坏或不可读取时保留原文件、暂停采集，提供重试及清空入口，避免新记录静默覆盖原缓存。剪贴板访问拒绝、文本读取失败、写入失败均有状态提示。日志不记录文本内容、文件原始数据或敏感标识。

## 本地化

界面只做简体中文和英文，跟随 macOS 系统语言，不在设置里放语言开关。源文案是中文，放在 `ClipboardHistory/Localizable.xcstrings`；英文写在同一份目录的 `en` 本地化里。工程 `developmentRegion` 为 `zh-Hans`。

SwiftUI 字面量（`Text("设置")`、`Section`、`help`、`accessibilityLabel` 等）走 `LocalizedStringKey`。Store、模型标题、退出确认框没有 SwiftUI 环境，使用 `String(localized:)`，同样查这份目录。`Barclip`、开发者姓名「陈云涛」、邮箱、仓库地址和版权姓名 `Yuntao Chen` 不翻译。

状态提示不再用 `message.hasPrefix("无法读取")` 这类易随翻译失效的判断，改为 `StatusMessage.allowsRetry`。

## 资源与范围

一个应用级监控 Task；重复启动不重复监听，停止可重启。SwiftUI LazyVStack 延迟构建记录视图，文本预览最多 160 字符，图片列表显示等比缩略图。原始文本和 PNG 完整保留。单条文本超过 1 MiB 或图片超过 30 MiB 时跳过并提示。文本和图片各自按容量裁剪。

敏感/临时标记（ConcealedType、TransientType）会被跳过。此筛选依赖源应用标记，不保证识别所有敏感文本。未标记的纯文本仍会作为文本记录。图片判定只看是否存在 PNG / TIFF / JPEG 位图：有位图就记入图片历史，即使同时带 `fileURL`（覆盖系统截图保存到桌面后再复制、以及部分 Finder 图片复制）。仅有文件引用、没有位图的剪贴板（普通 Finder 文件）仍跳过，避免把路径当图片或文本收入。
