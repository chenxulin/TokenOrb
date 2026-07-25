## 更新内容

### macOS 与 Windows 功能、效果对齐

- 将 Windows 版的双层水波、外圈呼吸、球体脉冲、流动高光、额度颜色阈值和文字显示效果迁移到 macOS。
- 对齐额度详情窗口、重置倒计时、外观设置、尺寸范围、悬浮球拖动、显示/隐藏和菜单栏交互。
- 对齐 Codex 启动/关闭跟随、账号切换、实时重连、失败退避、本地快照兜底和日志轮转行为。
- macOS 同时支持 Apple Silicon（arm64）和 Intel（x86_64）。

### 问题修复

- 修复 Windows 在应用失去焦点后右键菜单仍可能保持打开的问题。
- 将相同的菜单失焦关闭行为同步到 macOS。
- 加强旧请求、旧账号和旧本地快照保护，避免异步结果覆盖当前账号额度。

### 发布包调整

- Windows 提供 MSI 安装包和免安装 EXE。
- macOS 改为 DMG，内含可拖入 Applications 的 `Token Orb.app`。
- Windows 与 macOS 分别提供独立源码压缩包和 SHA-256 校验文件。
- Release 不再上传 README、通用程序 ZIP 或混合平台源码包。

## 下载与安装

### Windows

- 推荐安装：`TokenOrb-Windows.msi`
- 免安装运行：`TokenOrb-Windows.exe`

### macOS

- 下载 `TokenOrb-macOS.dmg`，打开后将 `Token Orb.app` 拖入 Applications。
- 当前 macOS 包采用 ad-hoc 签名、尚未进行 Apple 公证。若首次启动提示无法验证开发者，请在 Finder 中按住 Control 点击应用并选择“打开”。

## 源码与校验

- Windows 源码：`TokenOrb-Windows-source.zip`
- macOS 源码：`TokenOrb-macOS-source.zip`
- Windows 校验：`TokenOrb-Windows.sha256`
- macOS 校验：`TokenOrb-macOS.sha256`

完整变更：[v1.4.0...v1.5.0](https://github.com/chenxulin/TokenOrb/compare/v1.4.0...v1.5.0)
