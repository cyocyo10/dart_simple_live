<p align="center"><img width="128" src="assets/logo.png" alt="Simple Live logo"></p>
<h2 align="center">Simple Live · cyocyo10 维护版</h2>

基于 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) 的个人维护 fork。这里按自己的使用需求开发，重点把 AllLive 的 Windows 体验维护在 Dart 客户端中。原作者与本 fork 分别维护；本 fork 的问题请提交到[本仓库 Issues](https://github.com/cyocyo10/dart_simple_live/issues)。

## 下载与分支

| 入口 | 用途 | 产物 |
| --- | --- | --- |
| [master 构建](https://github.com/cyocyo10/dart_simple_live/actions/workflows/ci.yaml?query=branch%3Amaster) | 稳定分支，GitHub 默认展示 | Windows 便携版、MSIX、Android APK |
| [dev 构建](https://github.com/cyocyo10/dart_simple_live/actions/workflows/ci.yaml?query=branch%3Adev) | 日常开发和提前体验 | 同上，可能含尚未人工验收的改动 |
| [Releases](https://github.com/cyocyo10/dart_simple_live/releases) | 维护者公开发布的版本 | 从通过构建的标签草稿审核后发布 |

在 Actions 中打开成功的 **Fork Build**，从 Artifacts 分别下载 `windows-portable`、`windows-msix` 或 `android-apk`。下载 artifact 通常需要登录 GitHub，文件有保留期限；它与公开 Release 是不同渠道。当前版本和发布状态见 [CHANGELOG](CHANGELOG.md)，没有公开 Release 时请使用成功构建的 artifact。

Windows 便携包解压后从 `Simple Live.exe` 启动，旁边的 `runtime/` 必须保留；MSIX 是单独的安装包。便携版数据仍写入当前用户应用数据目录。更新前关闭全部旧窗口，完整解压新包；详见[迁移与数据说明](docs/ALLLIVE_MIGRATION.md)。

## 本维护版的主要改动

- 独立直播窗口，各自切换音量、清晰度、全屏和小窗；跨窗口共享收藏、历史、设置与账号。
- 按 AllLive 体验调整弹幕字号、字体、字重与描边，并修复样式缓存。
- 鼠标滚轮/上下拖动调音量，点击音量按钮显示滑块；Windows 与手机分别适配菜单和布局。
- 改进登录入口、窗口关闭、启动反馈、历史排序与双列显示，补充诊断导出和数据迁移验证。

详细实现、自动验证与仍需真人验收的边界见 [AllLive 迁移说明](docs/ALLLIVE_MIGRATION.md)。

## 维护范围

直播平台：虎牙、斗鱼、哔哩哔哩、抖音。平台接口可能变化，实际可用性以当前运行结果为准。

| 客户端 | 本 fork 的状态 |
| --- | --- |
| Windows | 重点维护；portable / MSIX 分别构建，自动回归覆盖多窗口与存储；真实账号、DPI 和使用手感仍需人工确认 |
| Android | 持续构建 APK；移动端体验单独验证 |
| macOS / Linux / iOS / Android TV | 保留源码，尚未纳入本维护版持续发布承诺 |

## 开发与维护

Flutter 3.38.x / JDK 17。`simple_live_core` 是直播平台核心库，`simple_live_app` 是主客户端；`simple_live_tv_app` 和 `simple_live_console` 保留各自入口。

- [贡献与本地验证](CONTRIBUTING.md)
- [独立维护、上游补丁、dev/master 与发布流程](docs/FORK_MAINTENANCE.md)
- [Astra 主会话的项目 AGENTS.md](AGENTS.md)
- [历轮修改与构建证据](docs/worklog/README.md)

## 来源、参考与许可

原项目：[xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)。本 fork 保留原作者历史、版权及 [LICENSE](LICENSE)。上游是可选的补丁来源，不自动覆盖本 fork 的分支或版本。

桌面交互参考 [AllLive](https://github.com/xiaoyaocz/AllLive)，实现对照参考 [Pure Live](https://github.com/liuchuancong/pure_live)。第三方实现和本地依赖补丁继续保留对应许可证与来源说明；引用来源不表示由原作者为本 fork 提供支持。

以下保留原项目的参考列表：

[AllLive](https://github.com/xiaoyaocz/AllLive) `本项目的C#版，有兴趣可以看看`

[dart_tars_protocol](https://github.com/xiaoyaocz/dart_tars_protocol.git)

[wbt5/real-url](https://github.com/wbt5/real-url)

[lovelyyoshino/Bilibili-Live-API](https://github.com/lovelyyoshino/Bilibili-Live-API/blob/master/API.WebSocket.md)

[IsoaSFlus/danmaku](https://github.com/IsoaSFlus/danmaku)

[BacooTang/huya-danmu](https://github.com/BacooTang/huya-danmu)

[TarsCloud/Tars](https://github.com/TarsCloud/Tars)

[YunzhiYike/douyin-live](https://github.com/YunzhiYike/douyin-live)

[5ime/Tiktok_Signature](https://github.com/5ime/Tiktok_Signature)
