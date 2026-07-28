# TokenOrb v1.5.4 发布说明

## 2026-07-28 v1.5.4 更新

### macOS 窗口交互

- 修复“个性化外观”在点击卡片外部或切换到其他应用后自动关闭的问题；窗口现在会保持打开，方便连续调整。
- “关于 TokenOrb”改为独立窗口生命周期，打开或关闭时不再联动收起额度详情等其他卡片。
- “关于 TokenOrb”的 `Esc`、确定按钮和标题栏关闭按钮统一为可复用的隐藏逻辑；重复打开会聚焦已有窗口。
- 修复非交互式悬浮球预览可能误改窗口鼠标穿透状态的问题。

### 系统外观适配

- “个性化外观”及自定义取色器会随 macOS 浅色/深色外观实时切换背景、卡片、边框、文字、选中态和按钮配色。
- “关于 TokenOrb”会随系统外观切换画布、页脚、标志结构线条和操作按钮配色。
- 额度详情卡同步适配浅色/深色外观，并针对状态文字、进度条、重置区域和辅助信息提升对比度。

### 实时额度可靠性

- 为 Codex app-server 初始化和额度查询增加 15 秒响应超时，避免接口无响应时长期停留在连接状态。
- 超时后会清理当前请求并进入既有重试与本地快照恢复流程。
- macOS 构建脚本新增可选 Swift SDK 路径与 SwiftPM 沙箱开关，便于受限构建环境稳定产出。

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

完整变更：[v1.5.3...v1.5.4](https://github.com/chenxulin/TokenOrb/compare/v1.5.3...v1.5.4)
