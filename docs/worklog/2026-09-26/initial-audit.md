> 历史快照：本报告记录实现前的发现，不代表当前版本仍存在这些问题。最终修复、验证和剩余限制见[工作记录](README.md)及[迁移说明](../../ALLLIVE_MIGRATION.md)。部分临时源码引用属于当时环境，原始记录已在本机私有归档保留。

# AllLive → Dart 迁移审查（2026-09-26）

结论：当前 dart_simple_live 尚未完整实现可替代 AllLive 的使用体验，不能据此宣布迁移完成。四个平台的主要观看流程已有实现；阻断项集中在独立窗口的数据一致性，以及弹幕样式和桌面操作对等。

用户确认的目标：以 AllLive 现有体验为标准，在 Dart 中保留多个直播间独立窗口、各自全屏/小窗、共享收藏和设置，之后只维护 Dart；Pure 作为实现参考。用户另指出弹幕视觉上偏小、偏细，与 AllLive 明显不同，调整字号感觉作用不大。Pure 的额外站点、录制、多画面分屏不自动纳入必迁范围。

## 基线与证据边界

| 项目 | 本地 HEAD |
|---|---|
| AllLive | c6951df959b7ead0d93edc087188788b49f1e273 |
| dart_simple_live | 0a3967e651c895d400e9535706d3daca9c505bb5 |
| pure_live | 9b376ec9ef25b532296871073a39075f6f9db397 |

以当前源码中可观察的行为为需求基线。本次没有独立的完整需求规格可逐条签收，不给出虚假的完成百分比。

审查覆盖 AllLive.Core/UWP/Console、Dart Core/主 APP，并补查 TV/Console 的入口和测试。Pure 定向参考多画面、小窗和弹幕设置实现，未宣称完整审查 Pure。

未改动三个项目业务源码。原工作区仅根仓库已有未跟踪 `.grok/`；Dart/Pure 工作区保持干净。离线复现产物只写入本报告所在临时目录。

## 需求覆盖矩阵

“已实现”仅指源码有完整对应路径，不等于本次在设备上验收通过。

| 需求 | Dart 现状 | 迁移判断 |
|---|---|---|
| B站/斗鱼/虎牙/抖音接入 | 四站均注册、实现接口 | 已有基础 |
| 推荐、分类、房间详情 | 四站有对应实现 | 已实现，在线可用性待验 |
| 关键词搜索 | 有实现 | 抖音房间号/链接的精确搜索行为未对等 |
| 清晰度、线路切换、播放地址 | 有实现 | B站未登录取流兼容策略需对照 |
| 弹幕接收与聊天列表 | 有实现 | 断连恢复需故障测试 |
| B站醒目留言 | 两端均有；其他三站两端均无 | 无新增差异 |
| 收藏、取消收藏、刷新状态 | 有实现 | 多窗口事件可能丢失 |
| 观看历史、删除、清空 | 有实现 | 多窗口同步和本地 JSON 互导不完整 |
| 直播/回放状态 | 有三态接口 | 虎牙实现没有返回回放态 |
| 独立直播窗口 | Windows 下启动独立进程 | 有功能，数据一致性未达到替代条件 |
| 全屏、窗口内铺满、置顶小窗 | 有对应控制方法 | 原生切换、关闭、焦点及窗口恢复待验 |
| 桌面快捷键 | 明确处理 Escape | AllLive 的音量/小窗/全屏/截图/弹幕键未显式迁移 |
| 弹幕字号、粗细、透明度、速度、区域 | 有设置及房间内更新入口 | 字号语义、小窗策略、描边和跨窗口同步不对等 |
| 字体选择/字形一致性 | 应用主题指定 Windows 微软雅黑，弹幕参数未显式指定字体 | 不能视为弹幕字体已对齐；需实际渲染对照 |
| B站、抖音账号 | 有服务与站点参数接线 | 独立窗口凭据更新不完整 |
| 斗鱼账号 | 可手工设置 Cookie | 原版内置登录流程未完整迁移，账号页仍显示“无需登录” |
| 收藏本地 JSON 导入导出 | 与 AllLive 的字段格式相容 | 可复用，仍需真实样本往返验证 |
| 历史本地 JSON 导入导出 | 缺少独立文件入口 | WebDAV/远程同步覆盖部分替代场景 |
| 远程同步、局域网同步、WebDAV | 有相关实现 | 服务器和端到端效果未验证 |
| TV 客户端 | 有独立入口，账号初始化主要为 B站 | 不能把主 APP 完成状态直接套用到 TV |
| Console | 有取直链/弹幕命令 | 原版无参数交互菜单、短链解析未完全对应 |

## 必须先解决的多窗口缺陷

### P1：子窗口会抢消费共享事件，导致主窗口漏收藏/历史

Dart 每个子窗口复制 Hive 数据并注册自己的 FollowService。直播间初始化调用 `loadData()`，继而消费共享目录中的事件；消费方法只检查 baseDir，没有限定主窗口。处理成功后会把文件改名为 `.processed`，其他窗口便不再处理。

触发：一个子窗口写入关注/历史事件，另一个子窗口加载关注数据或定时刷新，先于主窗口消费。结果可能只更新子窗口副本，主窗口记录遗漏。

证据：[子窗口初始化](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/main.dart#L200)、[直播间触发读取](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/live_room/live_room_controller.dart#L112)、[消费入口](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_service.dart#L146)、[公共事件消费](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_sync_service.dart#L205)。

离线最小复现保留原服务逻辑，仅替换日志和模型依赖，模拟角色顺序，结果：`subwindow consumed follow event; parent received 0`。这是同步服务层复现，不是 Windows GUI 实测。

### P1：同一设置在并发更新时可能丢失新值

设置按固定 key 文件覆盖写入；读端先读取内容、应用旧值，然后把同一路径归档。若期间另一窗口覆写新值，新值会一起被归档，后续无法消费。

证据：[设置写入](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_sync_service.dart#L139)、[设置读取和归档](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_sync_service.dart#L159)。

离线确定性注入该时间窗口，结果：`applied=[10]; archived=90`。说明新值 90 未生效，已被当作处理完的文件归档。

### P1：窗口间设置/账号只有快照和不完整单向回传

新窗口复制 localstorage/followuser/followusertag/history，漏掉 danmushield。已有屏蔽词默认不能随新窗口正确继承。

主窗口变更不向已打开子窗口广播；子窗口回传设置后，接收端只写 Hive，没有更新正在使用的 AppSettingsController 或账号服务。主窗口更改字号、屏蔽词、登录或退出后，已有窗口可能继续使用旧状态。

证据：[复制清单](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/main.dart#L247)、[只写持久层](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_service.dart#L213)、[设置初始化](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/app/controller/app_settings_controller.dart#L25)、[B站凭据注入](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/bilibili_account_service.dart#L57)。

AllLive 以独立 view 运行直播页，共享应用数据库。该原版基线可见 [窗口创建](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Helper/MessageCenter.cs#L98) 与 [共享数据库及串行访问](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Helper/DatabaseHelper.cs#L15)。不据此推断原版所有设置都能无延迟刷新。

## 弹幕体验对照

1. **字号单位不同。** AllLive 暴露 0.1～2 的字号缩放，Dart 为 8～48 的字号值、默认 16。数值不能直接互抄，应建立视觉对应关系。[AllLive 缩放控件](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Views/LiveRoomPage.xaml#L529)、[Dart 字号控件](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/settings/danmu_settings_page.dart#L120)。
2. **小窗策略缺失。** AllLive 成功进入 CompactOverlay 后将字号缩放设为 0.5、滚动时长设为 6 秒，退出恢复原设置。Dart 的 enterSmallWindow 改窗口大小/置顶，没有更新弹幕字号和时长，继续使用普通窗口参数。[AllLive 小窗](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Views/LiveRoomPage.xaml.cs#L1471)、[Dart 小窗](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/live_room/player/player_controller.dart#L313)。这能解释部分小窗比例差异，但用户具体观感仍需界面对照。
3. **描边控制没有接通。** AllLive 提供重叠、无边、描边模式；Dart 描边设置 UI 和渲染 strokeWidth 传参均被注释。不能把持久层仍有 danmuStrokeWidth 当作功能已完成。[AllLive 样式](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Views/LiveRoomPage.xaml#L552)、[Dart 注释设置](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/settings/danmu_settings_page.dart#L181)、[渲染初始化](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/live_room/player/player_controls.dart#L682)。这不表示第三方库完全不描边，而是用户无法沿该代码路径配置。
4. **弹幕字体未显式固定。** Windows 应用主题指定 Microsoft YaHei，但 DanmakuOption 未传字体家族，也无弹幕字体选择项。后续已核对 pub.dev 官方 0.2.7 源码：渲染器直接创建 ui.ParagraphBuilder，没有从 Theme 读取字体家族，也没有显式指定字体。实际系统回退字形仍未经设备验证，不能断言当前实际用了某个具体字体。[应用主题](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/app/app_style.dart#L22)、[弹幕参数](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/live_room/player/player_controls.dart#L687)。原版使用 NSDanmaku，此次未取得其默认字体的可验证渲染证据，因此不编造“一样字号就一样大”的映射。
5. **设置生效路径不统一。** 弹幕 widget 通过 `??=` 缓存；房间内设置面板拿到 DanmakuController 后会显式 updateOption，全局设置页没有该 controller。再叠加跨窗口仅写持久层而不更新运行状态的问题，不能保证所有窗口立即响应设置。[缓存](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/live_room/player/player_controls.dart#L684)、[设置更新](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/settings/danmu_settings_page.dart#L232)。不能把这个结论扩大为房间内字号调整完全无效。

Pure 可参考 [紧凑弹幕字号/轨道/速度计算](/root/AllLive/AllLive/pure_live/lib/common/utils/compact_danmaku_metrics.dart:22)、[字体和描边归一化](/root/AllLive/AllLive/pure_live/lib/common/utils/compact_danmaku_metrics.dart:68)、[弹幕设置模型](/root/AllLive/AllLive/pure_live/lib/common/services/settings/danmaku_settings_controller.dart:64)。应按 AllLive 视觉和交互校准，不能直接照搬 Pure 默认值即宣布对等。

### 根据“偏小、偏细、调整不明显”追加的依赖源码核对

项目声明 `canvas_danmaku: ^0.2.7`。本次从 [pub.dev 官方 0.2.7 归档](https://pub.dev/api/archives/canvas_danmaku-0.2.7.tar.gz) 下载源码到临时目录，只读审查，未升级或安装依赖。APP 没有本地 lock/package_config，不能把该源码核对说成用户当前安装包依赖已取证。

- **字重索引错误（源码确定）：** APP 设置允许 1～9，并将该值原样传入；0.2.7 使用 `FontWeight.values[fontWeight]`，Flutter 的列表只有索引 0～8。因此标签与实际重量错位，“极粗”传入 9 会在渲染读取时越界。这是独立缺陷；不能说它单独证明了“看着偏细”的全部原因。[APP 设置](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/settings/danmu_settings_page.dart#L137)、[库字重读取](/tmp/alllive-dart-audit-20260926/canvas_danmaku_0.2.7/lib/utils/utils.dart:11)。
- **只改字重不更新旧字形（源码确定）：** updateOption 仅在 fontSize 改变时清理 Paragraph 缓存，字重改变不会清理；绘制时缓存通过 `??=` 复用。所以已经在屏幕上的弹幕可保留原粗细，新到弹幕才按新字重生成。[缓存失效条件](/tmp/alllive-dart-audit-20260926/canvas_danmaku_0.2.7/lib/danmaku_screen.dart:324)、[缓存复用](/tmp/alllive-dart-audit-20260926/canvas_danmaku_0.2.7/lib/scroll_danmaku_painter.dart:57)。
- **字号有可用更新路径，不能一概说失效：** 0.2.7 的 updateOption 会因字号变化清理字形缓存。直播间面板传入当前控制器、并走该调用；全局设置页没有绑定控制器，其他窗口又没有广播，这两种入口明确不能保证更新正在播放的弹幕。如果用户在同一直播间面板调整字号仍无明显变化，仍需实际 Windows 运行验证，不能用源码推断代替复现。
- **字体和描边受旧版 API 限制：** 0.2.7 直接使用 ParagraphBuilder，未从应用 Theme 继承 fontFamily；描边宽度写死为 2。官方变更记录记载可配置描边宽度在 0.3.0 加入，字体家族选项在 0.3.1 加入；当前 `^0.2.7` 约束不包含这两个版本。[官方变更记录](https://pub.dev/packages/canvas_danmaku/changelog)、[当前库绘制逻辑](/tmp/alllive-dart-audit-20260926/canvas_danmaku_0.2.7/lib/utils/utils.dart:5)。因此仅给应用主题换字体不能解决这条弹幕绘制路径。

后续修复应包括字重值域/旧值迁移、字体显式指定、描边接线、样式变化缓存失效，以及跨窗口设置广播。视觉验收应以 AllLive 相同文本、相同窗口/DPI 下的结果为标准；不要仅将默认字号从 16 改成另一个数字就宣布修复。

## 其他对等缺口及待验证差异

- **快捷键缺口：** AllLive 显式支持上下调音量、F8/T 小窗、F12/W 窗口内铺满、F11/F/Enter 全屏、F10 截图、F9/D 弹幕开关。Dart 应用层明确可见的全局处理主要为 Escape；播放器使用自定义控件，没有找到对应映射。原生播放器是否额外处理某些按键需实测。[AllLive 快捷键](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/Views/LiveRoomPage.xaml.cs#L447)、[Dart 子窗口按键](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/app/sub_window_app.dart#L95)。
- **虎牙回放状态丢失：** AllLive 识别 REPLAY；Dart getLiveStatusDetail 只返回 2/1，没有 3，收藏和历史不能正确展示回放态。[AllLive](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.Core/Huya.cs#L492)、[Dart](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_core/lib/src/huya_site.dart#L710)。不能把非直播的所有实际响应一概称为未开播。
- **抖音精确搜索未迁移：** AllLive 的搜索识别数字房间号及抖音链接，Dart 主搜索直接调用关键词 API。工具页仍可解析部分链接，因此是搜索入口行为缺口，不是整个项目完全不能打开链接。[AllLive](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.Core/Douyin.cs#L659)、[Dart Core](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_core/lib/src/douyin_site.dart#L656)、[客户端接线](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/search/search_list_controller.dart#L33)。
- **账号操作体验：** 斗鱼手填 Cookie 已接入，不能报为完全不支持账号；但原版内置登录窗口与 Dart 账号页禁用入口不对等。[Dart 账号页](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/mine/account/account_page.dart#L41)、[实际 Cookie 设置](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/settings/other/other_settings_page.dart#L67)。
- **历史文件互导缺口：** 原版可以选本地 JSON 文件导入、导出；Dart 观看记录页缺少此入口。Dart 已有远程同步和 WebDAV 历史备份恢复，因此不应写成完全不能迁移历史。[AllLive](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/ViewModels/HistoryVM.cs#L169)、[Dart 历史页](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/mine/history/history_page.dart#L18)、[WebDAV 备份](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart#L185)。收藏格式已有兼容路径：[原版字段](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.UWP/ViewModels/FavoriteVM.cs#L261)、[Dart 导入](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/services/follow_service.dart#L495)。
- **无效链接反馈异常：** parse 返回空列表后，调用方用 `isEmpty && first == ""`，会读取空列表的 first 并抛异常，不能正常显示“无法解析”。[Dart](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_app/lib/modules/mine/parse/parse_controller.dart#L23)。静态证据，无 GUI 复现。
- **B站匿名取流兼容差异：** AllLive 无 Cookie 时走旧接口，Dart 一律走 v2。确认的是旧兼容路径缺失，未联网证明 v2 在所有匿名场景失败。[AllLive](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.Core/BiliBili.cs#L221)、[Dart](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_core/lib/src/bilibili_site.dart#L131)。
- **弹幕错误恢复差异：** Dart WebSocket onError 只上报，onDone 才安排重连；AllLive 抖音错误/关闭处理更完整。需注入错误不带关闭、备用线路、退出后禁止重连等情形；不能据此笼统宣布 Dart 弹幕无法重连。[Dart](https://github.com/cyocyo10/dart_simple_live/blob/0a3967e651c895d400e9535706d3daca9c505bb5/simple_live_core/lib/src/common/web_socket_util.dart#L116)、[AllLive](https://github.com/cyocyo10/AllLive/blob/c6951df959b7ead0d93edc087188788b49f1e273/AllLive.Core/Danmaku/DouyinDanmaku.cs#L471)。

## 已做验证

- 使用已有 Dart 3.13.2 运行 simple_live_core 的 `dart analyze --format machine`：退出码 0；0 error、0 warning、10 条 info lint。
- 两项同步服务离线复现通过，证明上述事件被子窗口消费及设置覆写丢失。复现脚本位于 [follow_sync_repro.dart](follow_sync_repro.dart)，未访问用户实际数据、未连接直播站点。
- APP/TV 测试仍是计数器模板；Console 测试为空断言；Core 测试主要为外站在线集成测试，未执行。CI build 配置没有 analyze/test 阶段。这些不足以证明功能对等。
- 本机为 Linux，本次没有 Windows 原生窗口、真实播放、字体/DPI、内存和多屏实测，也未构建安装包。

## 单项目迁移顺序与退出条件

1. **先修独立窗口的数据模型。** 明确唯一持久化写入者、请求确认和版本化状态广播；窗口保留自己的播放与弹幕会话，收藏/设置/账号由一致的权威状态提供。不要继续把每个子窗口的数据库副本当作长期独立真相。若继续采用多进程，应明确主窗口关闭后的数据服务存活和重连策略。
2. **同时完成弹幕对等。** 根据 AllLive 建立普通窗口/小窗的视觉基准，校准字号、字形、粗细、描边、透明度、速度和显示区域；切换后恢复原值；房间内设置、全局设置和其他窗口统一生效。Pure 的字体/小窗计算可作局部参考。
3. **补桌面操作和数据迁移。** 补快捷键、斗鱼登录体验、历史本地互导、状态及搜索差异，验证收藏/历史迁移前后数量与关键字段一致；账号迁移必须使用现有授权数据或重新登录，不能假设所有凭据可直接搬运。
4. **完成 Windows 对照验收。** 至少覆盖 3 个独立直播窗口同时播放、同房间重复打开、独立切画质/线路/音量、窗口全屏/小窗往返、关闭任意窗口、主窗口关闭和重启、网络断连恢复，以及共享收藏/历史/设置的一致性。弹幕以同一组文本，在相同窗口尺寸和 Windows 100%/125%/150% DPI 下对比字形与占屏比例；这些是待执行门槛，不是已通过结果。
5. **验收后只维护 Dart。** 新开发集中在 Dart，AllLive 保留冻结的可运行基准作回归对照；达到上述使用体验后再归档原版。无需同时持续开发两个实现，也无需将 Pure 整个合并进来。
