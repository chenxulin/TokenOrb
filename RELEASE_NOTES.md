## 更新内容

### 个性化外观

- Windows 与 macOS 采用一致的新版外观设置界面，支持 24–160 px 悬浮球大小、六种预设主题色和自定义取色。
- 新增 Wing、Aureole、Spear、Pearl、Thunder 五种数字风格，并可选择 30、60、90、120、180 FPS 动画帧率。
- 新增实时悬浮球预览；尺寸、主题色、数字风格和帧率变化会立即反映在预览中。
- 尺寸滑杆下方实时显示当前 px 数值，并保留更紧凑的手动输入框。
- 外观设置区按最大预览尺寸固定占位，调整悬浮球大小时不再上下移动。
- Windows 与 macOS 首次安装默认使用 65 px、`#2FA4EB`、Spear、60 FPS；已有完整外观配置继续优先使用。

### 悬浮球动画与渲染

- 新增前后双层水波动画，背景波以不同速度反向移动，并处理循环接缝以保持连续。
- 新增外环呼吸、球体轻微脉动、移动光泽和高光变化，让悬浮球更有层次感。
- 动画按所选帧率调度，并限制长时间停顿后的单帧增量，减少恢复时的视觉跳变。
- Windows 与 macOS 统一动画速度、光影、边框、波浪可见高度和数字排版规则。

### 跨平台交互与一致性

- 统一产品显示名称为 TokenOrb，并同步 Windows、macOS、安装器和发布产物中的版本信息。
- 改进 Windows 悬浮球右键菜单激活与菜单布局，降低透明置顶窗口下菜单无法正常打开的概率。
- macOS 外观窗口、自定义取色器、菜单与 Esc 关闭行为与 Windows 版本保持一致。
- “跟随 Codex”统一为随 Codex 启动和退出，相关菜单、提示与文档同步更新。

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

完整变更：[v1.5.1...v1.5.2](https://github.com/chenxulin/TokenOrb/compare/v1.5.1...v1.5.2)
