# Token Orb v1.0

Token Orb 是一个 Windows 悬浮球，可通过本机 Codex 实时接口显示当前账户的剩余额度。项目同时提供便携版 EXE 和按用户安装的 MSI，不需要管理员权限。

## 发布文件

- `TokenOrb.exe`：单文件便携版。
- `TokenOrb.msi`：Windows Installer 安装包，安装到 `%LOCALAPPDATA%\Programs\Token Orb`，并创建开始菜单入口。
- `TokenOrb.zip`：包含便携版和使用说明。
- `TokenOrb.source.zip`：可直接作为 GitHub 仓库内容使用的源码包。
- `TokenOrb.md`：发布版使用说明。
- `TokenOrb.sha256`：上述发布文件的 SHA-256 校验值。

## 安装与使用

### MSI 安装（推荐）

1. 双击 `TokenOrb.msi` 完成当前用户安装。
2. 从开始菜单启动 Token Orb，或重新登录 Windows。
3. Token Orb 会在 Codex 桌面应用启动时出现，并在 Codex 关闭后退出悬浮球界面。

可从 Windows“已安装的应用”中卸载 Token Orb。卸载时会移除程序文件、开始菜单入口和由 MSI 创建的启动项；用户的外观与位置设置会保留。

### 便携版

1. 确保 Codex 已安装并已使用 ChatGPT 账号登录。
2. 双击 `TokenOrb.exe`。
3. 左键单击悬浮球查看完整额度；点击卡片之外的任意位置会自动收起卡片；拖动悬浮球可换位置。
4. 右键选择“外观”可按 1 px 调整直径（24–160 px），使用 6 种预设颜色或打开系统颜色选择器自定义颜色。

## 跟随 Codex 运行

- 默认启用“跟随 Codex 启动/关闭”。应用会为当前 Windows 用户登记名为 `Token Orb` 的启动项。
- Windows 登录后只保留一个低频、无界面的监测器；检测到 Codex 桌面窗口时启动悬浮球和实时接口，Codex 窗口关闭后约 2 秒内退出悬浮球及实时接口进程。
- 如果不希望跟随，可在右键菜单取消勾选；如需完全结束监测器，选择“退出”。
- 从旧版升级时会继续读取 `%LOCALAPPDATA%\CodexQuotaBall` 中的已有设置，并把可见启动项迁移为 `Token Orb`。

新设置保存在 `%LOCALAPPDATA%\Token Orb`。应用不会读取 `auth.json`，不会复制、显示或保存登录令牌。

## 数据来源

- 实时接口：启动本机 `codex app-server`，完成标准 `initialize` 握手后调用 `account/rateLimits/read`，每 30 秒主动刷新，并接收 `account/rateLimits/updated` 推送。
- 回退：如果实时接口暂时不可用，监听 `%USERPROFILE%\.codex\sessions`，解析 Codex 自己写入的 `rate_limits` 快照。
- 剩余百分比严格按服务端 `usedPercent` / `used_percent` 计算为 `100 - usedPercent`，不自行估算 token 消耗。

## 系统要求

- Windows 10 或 Windows 11
- 已安装并登录 Codex 桌面应用；关闭跟随功能后，也可仅配合 Codex CLI 使用
- Windows 自带 .NET Framework 4.x

## 本地构建

在 Windows PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -OutputDirectory .\dist
```

首次构建 MSI 时，脚本会从 WiX 官方 GitHub Release 下载 WiX Toolset v3.14.1 便携工具。下载支持中断续传，并校验固定 SHA-256；WiX 只用于构建，最终用户无需安装它。

WiX 来源：<https://github.com/wixtoolset/wix3/releases/tag/wix3141rtm>

## GitHub Release

源码已包含 `.github/workflows/release.yml`：

- 手动运行工作流会构建并上传全部 `Token Orb.*` 文件为 Actions Artifact。
- 推送 `v*` 标签（例如 `v1.0`）会同时创建 GitHub Release 并附加 EXE、MSI、ZIP、源码包、说明和校验文件。

发布公开版本前建议使用可信代码签名证书为 EXE 和 MSI 签名；未签名文件可能触发 Windows SmartScreen 提示。

## 常见问题

- 显示“实时”：当前数值直接来自 Codex app-server。
- 显示“本地”：实时接口连接失败时的降级状态；右键选择“立即刷新”可重试。
- 双击后没有出现悬浮球：默认跟随模式正在等待 Codex 桌面窗口；启动 Codex 后会自动出现。
- 找不到 Codex：可把环境变量 `CODEX_QUOTA_CODEX_PATH` 指向 `codex.exe` 的完整路径后重新启动。
- Windows 安全提示：当前构建未做商业代码签名，可使用 `TokenOrb.sha256` 核对文件完整性。

官方 Codex app-server 说明：<https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints>
