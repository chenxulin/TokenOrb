# TokenOrb v1.5.3 发布说明

## 2026-07-28 v1.5.3 更新

- macOS 应用包、系统进程和安装显示名称统一为 `TokenOrb`，应用包更名为 `TokenOrb.app`。
- 新增嵌套轻量 watcher：Codex 启动时拉起 TokenOrb 主应用，Codex 退出后主应用进程同步退出。
- 等待 Codex 时由 watcher 保留菜单栏入口，并提供立即检查、重新打开和诊断日志入口。
- 使用 `NSWorkspace` 启动/退出通知即时检测，保留 2 秒扫描兜底，并记录 Codex 候选进程与状态变化。
- 精确 Bundle ID `com.openai.codex` 不再受 Activation Policy 限制，避免 LaunchServices 状态导致误判。
- Windows 外观设置改为可从任务栏切换的非模态独立窗口；重复打开时激活现有窗口，不再被置顶悬浮球压在其他应用之上。
- 更新 Windows 界面截图，并补充未公证 macOS 应用的首次放行步骤。

## 2026-07-27 补充更新

- 左键点击悬浮球打开额度详情卡片后，Windows 与 macOS 均支持按 `Esc` 快速收起。
- Windows“个性化外观”窗口移除右上角重复的蓝色关闭按钮，继续使用底部“取消”或 `Esc` 关闭。
- 实时预览卡向右对齐；状态绿灯与“实时预览”固定在左上角，数字样式名称以醒目的粗体居中显示。
- 额度详情卡在没有额外积分时显示 `0`；套餐名称保留 `ChatGPT` 前缀，当前协议未提供倍率时显示 `ChatGPT Pro`。
- 页脚将“数据来源”与完整的年月日时分秒分列左右，只显示“实时数据”或“本地快照”，并移除重复的本机调用说明。
- “下轮重置”同时显示完整日期与右对齐倒计时；过期的 7 天额度按 7 天周期校正下一次重置，并正确处理跨年日期。
- “跟随 Codex 启动/退出”开关集中到托盘菜单；关闭跟随后仍保留托盘入口，悬浮球菜单同步精简显示控制文案。

## 主要更新内容

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

- 下载 `TokenOrb-macOS.dmg`，打开后将 `TokenOrb` 拖入“Applications（应用程序）”文件夹。
- 当前 macOS 包尚未经过 Apple 公证。首次启动被阻止后，请前往“系统设置 → 隐私与安全性”，在“安全性”区域允许打开 `TokenOrb`；完整步骤请查看 README 中的“macOS 安装”。

## 源码与校验

- Windows 源码：`TokenOrb-Windows-source.zip`
- macOS 源码：`TokenOrb-macOS-source.zip`
- Windows 校验：`TokenOrb-Windows.sha256`
- macOS 校验：`TokenOrb-macOS.sha256`

完整变更：[v1.5.2...v1.5.3](https://github.com/chenxulin/TokenOrb/compare/v1.5.2...v1.5.3)
