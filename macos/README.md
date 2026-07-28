# TokenOrb for macOS

这是 TokenOrb 的原生 macOS 客户端。Windows 版本保持原样，macOS 版本使用
Swift、AppKit 和 Swift Package Manager，不依赖第三方库。

## 安装

适用于 macOS 13 及更新版本，发布包同时支持 Apple Silicon 和 Intel Mac。

1. 从 GitHub Release 下载 `TokenOrb-macOS.dmg`，下载完成后双击打开。
2. 在安装窗口中，将 `TokenOrb` 拖到“Applications（应用程序）”文件夹。请不要
   直接在 DMG 中运行。
3. 打开 Finder 的“应用程序”文件夹，双击 `TokenOrb`。首次打开时，macOS 会阻止
   应用运行；看到提示后关闭提示窗口即可。
4. 点击屏幕左上角的苹果菜单，依次打开“系统设置 → 隐私与安全性”。
5. 向下找到“安全性”区域，找到与 `TokenOrb` 相关的拦截提示，点击旁边的放行
   按钮（通常显示为“仍要打开”），然后使用 Touch ID 或输入 Mac 登录密码，并
   再次确认打开。
6. 返回“应用程序”文件夹启动 `TokenOrb`。系统会记住这次选择，以后可以直接
   双击打开。

当前版本尚未经过 Apple 公证，因此首次安装需要手动允许一次。

### 常见问题

- **找不到放行按钮：**返回“应用程序”文件夹，再双击一次 `TokenOrb`，然后重新
  打开“隐私与安全性”。
- **放行后没有出现悬浮球：**`TokenOrb` 默认跟随 Codex 运行，请先启动 Codex。

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
- 使用嵌套轻量 watcher 进程级跟随 Codex：Codex 启动时拉起主应用，退出时结束主应用
- watcher 等待期间保留菜单栏入口，可立即检查、重新打开 TokenOrb 或查看诊断日志
- 使用 `NSWorkspace` 启动/退出通知即时响应，并保留 2 秒扫描兜底
- Codex 候选进程、识别状态和启动结果记录于 `~/Library/Application Support/TokenOrb`

## 构建

要求 macOS 13 或更新版本，并安装 Apple Command Line Tools：

```bash
xcode-select --install
bash macos/build_macos.sh
```

构建结果：

- `macos/dist/TokenOrb.app`
- `macos/dist/TokenOrb-macOS.dmg`
- `macos/dist/TokenOrb-macOS-source.zip`
- `macos/dist/TokenOrb-macOS.sha256`

运行：

```bash
open "macos/dist/TokenOrb.app"
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
CODEX_QUOTA_CODEX_PATH="/path/to/codex" open "macos/dist/TokenOrb.app"
```

若 Codex 使用了自定义数据目录，TokenOrb 与 Windows 版本一样支持 `CODEX_HOME`：

```bash
CODEX_HOME="/path/to/codex-home" open "macos/dist/TokenOrb.app"
```

TokenOrb 只在本机启动 `codex app-server`。应用不会上传或保存 Codex 登录凭据。
