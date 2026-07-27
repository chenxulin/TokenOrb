## 更新内容

### 实时额度与自动恢复

- 首次查询、手动刷新和失败恢复均先重启 app-server，再请求实时额度，避免继续使用旧进程中的认证或连接状态。
- 保留额度实时推送，并将正常轮询调整为每 20 秒一次；同一时间只允许一个额度查询，避免并发请求互相干扰。
- 实时查询失败后依次等待 5、10、15 秒重试三次，每次重试前都会重启 app-server。
- 三次重试仍失败时才显示最近一次会话的本地快照；兜底期间每 30 秒在后台重启 app-server 并尝试恢复实时数据。
- 实时查询恢复成功后立即切回实时额度，并清空失败计数、恢复正常轮询。
- 加强 Windows 与 macOS 的旧 app-server 终止及进程退出处理，避免残留进程导致重启或查询失败。

### 悬浮球显示与交互

- Windows 与 macOS 悬浮球统一使用居中的 16:9 透明预览区域，改善系统窗口预览效果。
- 透明区域保持鼠标穿透，只有悬浮球本体响应拖动、点击和右键菜单，不遮挡下方窗口。
- 详情窗口改为相对悬浮球本体定位；调整尺寸、拖动和屏幕边界约束时继续保留正确位置。

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

完整变更：[v1.5.0...v1.5.1](https://github.com/chenxulin/TokenOrb/compare/v1.5.0...v1.5.1)
