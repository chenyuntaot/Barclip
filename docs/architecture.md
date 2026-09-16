# 架构与技术决策

## 平台与入口

原生 Swift 6 + SwiftUI，最低 macOS 14（Observation）。不引入第三方运行依赖。
`ClipboardHistoryApp` 只创建 `MenuBarExtra`，不创建主窗口。生成的 Info.plist 设置 `LSUIElement = YES`，AppDelegate 同时设置 `.accessory` 激活策略。

使用菜单栏弹出面板中的设置页，避免为两个设置项引入独立窗口。`ClipboardMenuView` 本地管理页面切换，Store 通过 Environment 注入。

## 责任划分

- `Models/ClipboardEntry.swift`：原始文本、标识、时间和预览；保存策略枚举。
- `Services/PasteboardService.swift`：AppKit 剪贴板读写、类型筛选和访问拒绝判断。
- `Services/HistoryRepository.swift`：actor 隔离本机 JSON 文件读写。
- `Stores/ClipboardStore.swift`：Observation 状态、轮询、去重、容量裁剪、恢复与保存编排。
- `Views/ClipboardMenuView.swift`：历史、复制、清空、状态提示与设置入口。
- `Views/ClipboardSettingsView.swift`：容量与保存策略。

## 监听方式

使用应用生命周期内的 Swift Concurrency Task，每 500ms 检查 NSPasteboard.changeCount，仅变更后读取文本。菜单关闭后仍然工作，退出时取消。读前后校验 changeCount，避免读到跨版本内容。

没有使用私有通知或辅助功能注入。轮询成本低，但可能遗漏 500ms 内连续复制的中间值；如果后续要求完整捕获高频事件，需要重新评估此约束。

## 保存与错误恢复

默认只保存在内存；容量和保存策略通过 UserDefaults 保留。
持久化模式使用 `~/Library/Application Support/ClipboardHistory/history.json`。目录权限 0700，文件权限 0600，JSON 原子写入；文件并未加密。全部处理在本机完成，无网络请求。

选择 JSON 是因为第一期记录上限为 200，无复杂查询需求；未引入数据库或 SwiftData。以后若引入搜索索引、大规模媒体或大量记录，再评估存储方案。

磁盘操作在 actor 上执行，不在主线程编码、读取和写入。每份快照带单调递增版本，晚到的旧版本不会恢复已清空的数据。清空与切换为会话模式删除历史文件。正常退出会等待最新写入；保存失败时允许返回重试或明确选择仍然退出。

缓存损坏或不可读取时保留原文件、暂停采集，提供重试及清空入口，避免新记录静默覆盖原缓存。剪贴板访问拒绝、文本读取失败、写入失败均有状态提示。日志不记录文本内容、文件原始数据或敏感标识。

## 资源与范围

一个应用级监控 Task；重复启动不重复监听，停止可重启。SwiftUI LazyVStack 延迟构建记录视图，预览最多 160 字符，原始文本完整保留。单条文本超过 1 MiB 时跳过并提示，避免单条巨型内容长期驻留。

敏感/临时标记（ConcealedType、TransientType）及文件类型会被跳过。此筛选依赖源应用标记，不保证识别所有敏感文本。未标记的纯文本仍会作为文本记录。
