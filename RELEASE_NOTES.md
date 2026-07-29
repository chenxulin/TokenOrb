# TokenOrb v1.6.0 发布说明

## 2026-07-29 v1.6.0 更新

### 额度展示规则

- Windows 与 macOS 悬浮球统一优先展示 5 小时额度；当周额度耗尽时，立即切换显示周额度。
- 只有周额度可用时仍会展示周额度；未知或不受支持的额度窗口不再作为悬浮球数字的兜底来源。
- 补充跨平台规则校验，覆盖 5 小时额度、周额度耗尽和未知窗口等边界情况。

### macOS 交互与布局

- 优化额度详情窗口的动态高度计算，窗口会随可见额度卡片数量紧凑调整。
- 打开悬浮球右键菜单时自动收起额度详情，避免窗口与菜单重叠。
- “个性化外观”窗口改为更紧凑的尺寸、间距与操作按钮布局。

### 构建可靠性

- 新增统一的 `swiftpm.sh` 启动脚本，自动选择 Apple Swift 工具链并将 SwiftPM、Clang 缓存隔离到项目目录。
- 在受管或嵌套沙箱不可用时自动关闭 SwiftPM 内部沙箱，同时保留工具链、SDK、缓存和沙箱策略的手动覆盖入口。
- macOS 发布源码包现在包含 `swiftpm.sh`，README 同步更新开发与校验命令。

### Windows 品牌一致性

- 安装器、安装目录、开始菜单快捷方式与开机启动项统一使用 `TokenOrb` 名称。
- 升级安装时清理旧版 `Token Orb` 开机启动项，并增加构建期安装器身份检查。

## 下载与安装

### Windows

- 推荐安装：`TokenOrb-Windows.msi`
- 免安装运行：`TokenOrb-Windows.exe`

### macOS

- 下载 `TokenOrb-macOS.dmg`，打开后将 `TokenOrb` 拖入“Applications（应用程序）”文件夹。
- 当前 macOS 包尚未经过 Apple 公证。首次启动被阻止后，请前往“系统设置 → 隐私与安全性”，在“安全性”区域允许打开 `TokenOrb`；完整步骤请查看 README 中的“macOS 安装”。

## 源码与校验

- Windows 源码：`TokenOrb-Windows-source.zip`
- macOS 源码：`TokenOrb-macOS-source.zip`
- Windows 校验：`TokenOrb-Windows.sha256`
- macOS 校验：`TokenOrb-macOS.sha256`

完整变更：[v1.5.4...v1.6.0](https://github.com/chenxulin/TokenOrb/compare/v1.5.4...v1.6.0)
