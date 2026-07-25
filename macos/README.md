# Token Orb for macOS

这是 Token Orb 的原生 macOS 客户端。Windows 版本保持原样，macOS 版本使用
Swift、AppKit 和 Swift Package Manager，不依赖第三方库。

## 功能

- 菜单栏状态与桌面悬浮球
- 实时读取 Codex 5 小时和 7 天额度
- 点击悬浮球查看详细额度
- 右键悬浮球打开操作菜单
- 拖动悬浮球并保存位置
- 自定义悬浮球大小和颜色
- 检测 Codex 账号变化后自动重连
- 实时接口不可用时读取本地会话快照
- 可跟随 Codex 桌面应用启动和关闭

## 构建

要求 macOS 13 或更新版本，并安装 Apple Command Line Tools：

```bash
xcode-select --install
bash macos/build_macos.sh
```

构建结果：

- `macos/dist/Token Orb.app`
- `macos/dist/TokenOrb-macOS.zip`

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

Token Orb 只在本机启动 `codex app-server`。应用不会上传或保存 Codex 登录凭据。
