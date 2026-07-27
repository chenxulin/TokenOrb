# Token Orb for macOS

这是 Token Orb 的原生 macOS 客户端。Windows 版本保持原样，macOS 版本使用
Swift、AppKit 和 Swift Package Manager，不依赖第三方库。

## 安装

从 GitHub Release 下载并打开 `TokenOrb-macOS.dmg`，将 `Token Orb.app` 拖入
“Applications”。发布包同时支持 Apple Silicon 与 Intel。

当前安装包使用 ad-hoc 签名、尚未公证。若 macOS 提示无法验证开发者，请在
Finder 中按住 Control 点击应用并选择“打开”。

## 功能

- 菜单栏状态与桌面悬浮球
- 与 Windows 一致的双层水波、外圈呼吸、球体脉冲与流动高光动画
- 实时读取 Codex 5 小时和 7 天额度
- 点击悬浮球切换详细额度，失焦自动关闭，重置倒计时按秒更新
- 右键悬浮球打开操作菜单
- 拖动悬浮球并保存位置
- 自定义 24–160 px 悬浮球大小、主题颜色、五种数字样式和 30–180 FPS 动画帧率，保存或取消后再应用
- 检测 Codex 账号身份变化后自动重连，同账号令牌轮换不会误刷新
- 实时查询失败后按 5/10/15 秒重启重试三次；仍失败时读取本地会话快照，并每 30 秒尝试恢复实时数据
- 监听本地会话变化，并保留 60 秒兜底轮询
- 可跟随 Codex 桌面应用启动和退出

## 构建

要求 macOS 13 或更新版本，并安装 Apple Command Line Tools：

```bash
xcode-select --install
bash macos/build_macos.sh
```

构建结果：

- `macos/dist/Token Orb.app`
- `macos/dist/TokenOrb-macOS.dmg`
- `macos/dist/TokenOrb-macOS-source.zip`
- `macos/dist/TokenOrb-macOS.sha256`

运行：

```bash
open "macos/dist/Token Orb.app"
```

开发模式可用演示数据启动，不会调用 Codex：

```bash
swift run --package-path macos TokenOrb --demo
```

## 校验

```bash
swift run --package-path macos TokenOrbCoreChecks
```

## Codex CLI 查找

应用优先使用 Codex 桌面应用内置的 CLI，也会检查 `PATH`、Homebrew 和常见安装
路径。需要手动指定时：

```bash
CODEX_QUOTA_CODEX_PATH="/path/to/codex" open "macos/dist/Token Orb.app"
```

若 Codex 使用了自定义数据目录，Token Orb 与 Windows 版本一样支持 `CODEX_HOME`：

```bash
CODEX_HOME="/path/to/codex-home" open "macos/dist/Token Orb.app"
```

Token Orb 只在本机启动 `codex app-server`。应用不会上传或保存 Codex 登录凭据。
