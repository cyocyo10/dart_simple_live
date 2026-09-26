# AllLive → Dart 桌面迁移

本轮以 AllLive 现有 Windows 使用方式为基线：独立直播窗口、窗口各自播放和切换模式，共享收藏、历史、账号与设置。Pure 仅作参考。修改集中在 Dart；AllLive 原版已保存在远端和本机私有 bundle，原工作目录已按维护者要求清理，恢复信息见工作档案。

## 已接入

- Windows 多窗口仍采用独立进程。新用户默认开启；已有开关选择保留。各窗有独立播放器、音量、全屏和置顶小窗。
- 删除复制 Hive + 单向消费事件的机制。所有桌面进程使用同一版本化快照，操作在文件锁内串行提交，约 300 ms 刷新其他窗口。主窗口关闭后，直播窗口仍可保存。
- 共享收藏、标签、历史、设置、屏蔽词及账号参数；历史按观看时间合并。关闭窗口先响应并保存排队写入；保存超时/失败恢复窗口并提示，避免隐藏进程一直等待。
- 首次升级导入旧 Hive 和尚未处理的窗口事件，保留原文件。后续只读写 `Application Support/shared/state.json`；上一份快照位于 `state.backup.json`。损坏文件保留供排查，未来版本的存储格式不会被旧版本自动覆盖。
- 弹幕字号、字体、字重、描边实时更新。桌面新用户默认字号 25；已有字号保留，可在“弹幕设置 → 恢复 AllLive 弹幕风格”应用预设。字重 1～9 正确映射；小窗字号减半、时长 6 秒，退出恢复保存的设置。
- `canvas_danmaku` 基于 0.3.1 保留本地补丁，修复缓存重绘丢失字体和字体变化后的轨道计算。来源、许可证和移除条件见 `simple_live_app/plugins/canvas_danmaku/PATCHES.md`。
- 桌面视频区域按住鼠标左键上下拖动可调音量，上拖增大、下拖减小，按播放器高度 80% 对应 0–100% 的比例调节；两侧画面均调当前窗口音量。鼠标滚轮每格调音量 5%；音量提示不拦截鼠标，连续请求只保留最新待应用值。单击音量按钮打开滑块面板，可静音/恢复，点击外部或 Esc 关闭。桌面快捷键：↑/↓ 音量，F8/T 小窗，F12/W 窗口铺满，F11/F/Enter 全屏，F10 截图，F9/D 弹幕，Escape 退出窗口模式。文本输入和弹窗期间不抢按键。
- 桌面清晰度/线路使用按钮旁的选项菜单；手机继续使用原底部/侧边面板。桌面设置面板有宽高边界，窄窗口控制栏可拖动或用水平滚动条访问，音量提示不抢鼠标事件。
- 观看记录捕获打开房间的时间并传给子窗口，不再以接口返回时刻排序；刷新与重连保留原观看时间，较旧窗口不能覆盖同房间较新记录。历史页按行从左到右排列，常规字号下内容区约 840 px 起双列，窄窗口和大字号自动调整；平台状态与本地观看时间分行，房间键随数据保留。
- 窗口先显示轻量加载反馈，诊断日志记录启动阶段耗时。子窗口读取共享收藏与账号，但不重复定时刷新整份收藏或拉取 B 站账号资料；主动打开关注面板仍可刷新。共享轮询每 300 ms 检查文件元数据，变化时读取快照，约每 3 秒强制校验一次。极少数大小和修改时间均未改变的外部写入会等下一次强制校验，实际延迟还受调度和锁等待影响。
- 历史页增加 AllLive JSON 合并导入/导出；导入整份校验后写入，保留较新记录。删除等待保存成功后更新页面，未知平台记录可保留、导出或删除。
- 关注标签改名、分组、取消关注和房间别名转换在桌面端同一事务内保存；过期窗口的标签排序保留其他窗口新增的标签。标签筛选不再修改存储，标签变更会更新当前筛选。
- 列表刷新和关注/历史状态查询隔离旧请求，快速刷新、切换搜索和关闭页面后不会继续回写旧结果。
- 收藏本地导入、HTTP/SignalR 同步先完整校验后批量保存。WebDAV 先校验所有选中文件，保存失败显示部分完成情况；远程跨文件恢复及手机 Hive 不保证整体事务原子性。
- B站、斗鱼使用登录页；抖音从官方直播首页定位可见登录入口，避免旧 passport JSON 接口的 4031。提供加载进度、重试及浏览器/Cookie 后备，扫码成功无导航时也会检测登录态。Windows WebView 和 CookieManager 使用同一个应用数据目录中的环境。
- B站网页、扫码和手动 Cookie 登录先验证再保存；取消登录后拒绝旧响应，扫码不重复轮询/关闭页面。退出按平台清理网页 Cookie，不清除其他平台账号。登录保存完成后才提示成功。
- 分享链接解析使用平台域名边界和有界跳转，支持斗鱼 rid、抖音 reflow 及短链；网络无响应、循环跳转和页面关闭后不会崩溃或继续导航。
- 播放详情、清晰度、线路、重试、SC 和弹幕回调按请求归属处理；播放器打开、停止和跳转串行，退出后不会被旧请求重新打开。定时关闭的宽限计时器可取消，退出前等待数据和日志写入。
- 虎牙直播/回放/离线三态；抖音房间号和直播链接精确搜索；B站现代取流失败时回退旧接口；弹幕连接有界重试、备用端点和关闭后的回调隔离。

## 桌面显示

桌面沿用 Flutter Material 3 与用户选择的主题色，统一菜单和弹窗边界、间距、悬浮提示及键盘焦点；Windows 使用 Segoe UI Variable，并为中文提供系统字体回退。视频控件动画为 150 ms，系统要求减少动画时直接切换。窄窗口控制栏可横向滚动，大字号下增加可滚动内容宽度。参考微软的[字体规范](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography)及[布局指导](https://learn.microsoft.com/en-us/windows/apps/design/basics/content-basics)，并非原生 WinUI 控件实现。

## Windows 包和诊断

便携 ZIP 解压后的可见根目录：

```text
Simple Live.exe
runtime/
使用说明.txt
```

`runtime` 包含 Flutter、播放器和插件文件，需要随包保留。收藏、设置及日志存储在当前用户的应用数据目录。更新时先关闭所有旧版本窗口，再将新版本完整解压到新目录；避免旧、新存储协议同时运行。保留 MSIX 安装包。

在已安装 Flutter 和 Visual Studio C++ 桌面工具的 Windows 中，从仓库根目录运行：

```powershell
cd simple_live_app
flutter pub get
flutter build windows --release
./tool/windows/package-portable.ps1
./tool/windows/test-portable.ps1
```

输出：`simple_live_app/build/dist/windows-portable/SimpleLive-<版本号+构建号>-Windows-Portable.zip`。启动器测试覆盖 Unicode 路径/参数、工作目录、子进程和退出码。

统一的 Fork Build（dev/master/标签复用）将 Windows 拆成两个独立任务，可在 Actions 中分别查看状态和重跑失败任务：

| 任务 | Actions 下载项 | 内容 |
| --- | --- | --- |
| `build-windows-portable` | `windows-portable` | 无需安装的 `SimpleLive-<版本号+构建号>-Windows-Portable.zip` |
| `build-windows-msix` | `windows-msix` | MSIX 安装包 |

便携版直接执行 `flutter build windows --release`，再封装和测试启动器；MSIX 独立使用 `flutter_distributor` 打包。两者分别编译，任一任务失败不会取消另一个任务或阻止其上传产物。CI 的公共分析与回归检查由 portable 任务执行，整体 CI 成功仍要求所有任务通过。标签构建全部成功后，两种文件上传到同一版本的 Release 草稿；由维护者决定公开发布。

“其他设置”支持查看日志、打开目录、导出诊断 ZIP、安全清理。默认保留警告/错误，可开启详细调试日志后复现问题。日志按进程/会话区分，每份约 2 MB、每会话最多 5 段，按 14 天/50 MB 清理已结束会话；仍运行的窗口受文件锁保护。导出包只包含脱敏日志和运行信息，不包含收藏或账号配置文件。

## 验证与交接

自动验证入口：

```text
simple_live_app: flutter analyze --no-fatal-infos
simple_live_app: flutter test
simple_live_app: dart test/storage/shared_store_check.dart
simple_live_app: dart test/storage/shared_store_polling_check.dart
simple_live_app: dart test/diagnostics/diagnostic_writer_check.dart
simple_live_app: dart test/migration/transfer_check.dart
simple_live_app: dart tool/verify_login_session.dart
simple_live_app: dart tool/verify_room_link_parser.dart
simple_live_core: dart test test/migration_core_offline_test.dart
```

离线测试覆盖 3 个真实进程的 75 次并发写入、主进程退出后保存、较新历史合并、清空与替换传播、备份恢复、损坏拒绝、日志轮转与活跃进程保护、JSON 互导、重连故障、平台响应 fixture，以及 Hive 升级和弹幕/快捷键组件。

2026-09-26 首轮集成验证：Flutter 全部 38 项测试通过；核心 11 项离线测试通过；共享存储、日志、JSON 互导脚本通过；登录标记 16 项和链接解析 29 项检查通过。应用和核心静态分析为 0 error、0 warning，另有 60 条 info（样式/弃用等提示）。Flutter Dart/资源 bundle 构建通过。随后 `ed3b893` 的历史 GitHub 构建（旧构建已按维护者要求清理，记录归档于 [工作记录](worklog/2026-09-26/README.md)） Windows 与 Android 均成功，两个 job 均无 Actions 告警；Windows 便携包启动器原生测试通过。

1.14.0+11401 后续集成验证：应用完整 64 项 Flutter 测试通过；应用分析 0 error、0 warning，46 条 info。共享存储、日志、JSON 互导脚本通过；登录标记/入口 19 项及房间链接 29 项检查通过。新增覆盖抖音扫码无导航、关闭超时恢复/迟到请求、滚轮音量边界与提示命中、桌面/手机菜单分流及窄窗口控制栏。

1.14.1+11402 集成验证：应用完整 91 项 Flutter 测试通过；应用分析 0 error、0 warning，42 条 info。新增覆盖真实鼠标拖动、小窗拖动与窗口移动的手势竞争、音量菜单/静音/键盘焦点、慢播放器请求合并、启动页和深浅主题大字号、打开顺序与接口返回顺序相反、旧窗口不能回退同房记录、960/320 px 历史双列切换以及页面接收共享更新。共享存储并发及轮询脚本均通过：Linux 模拟 3 个窗口、1 MB 快照、空闲约 3.4 秒共完整读取 3 次，原 300 ms 完整轮询会调度 33 次；普通外部更新约 214 ms 同步，同大小/同修改时间的特殊替换约 3230 ms 被强制校验发现。这些是存储测试数据，不代表 Windows 窗口帧率或体感测试。

本地验证环境的 Flutter 自报 3.38.0，但内置 Dart 为 3.10.0 beta。依赖使用稳定 Dart 3.13.2 配合 FLUTTER_ROOT 解析，并在解析时临时限制 synchronized/build_daemon/sse 为该 Flutter 编译器支持的版本；临时覆盖文件已移除，未改变这些依赖的项目约束。CI 使用正常 Flutter 3.38.x 稳定版本解析依赖。

本次环境是 Linux。Windows 安装包原生构建已由 GitHub Windows runner 验证；WebView 真人登录、真实平台播放、关闭手感和字体视觉对照仍需 Windows 人工验收，不能由离线测试替代。验收建议：同时打开三个直播间及两个相同房间，独立切换画质/线路/音量；普通、小窗、窗口铺满、系统全屏往返；关闭主窗口继续收藏，重启后核对；跨窗口改变字号/字体/屏蔽词和账号；在 100%/125%/150% DPI 下与 AllLive 对比相同弹幕。

TV/Console 的独立入口、远程同步服务器/WebDAV 的线上端到端行为没有在本轮完成独立验收。当前不能把本轮桌面实现等同于 AllLive 全平台所有需求均已验收；旧 AllLive 的远端和本地备份可用于后续对照。

历轮修改、压缩前提交清单、最终成功构建、失败修复及 AllLive 本机清理记录见[工作档案](worklog/2026-09-26/README.md)。
