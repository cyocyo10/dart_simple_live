# 历轮 fork 提交清单

压缩前 dev：`2a1424bcf16524edafa95616e975fbcf692e7a3a`。共 56 条 fork 独有提交，含 2 条合并提交。以下是历史记录，不是现存 dev 的提交序列。原作者及上游贡献者的既有提交保持原 SHA、署名与父子关系。

| 原提交 | 日期 | 作者 | 内容 |
| --- | --- | --- | --- |
| `043cbf5dce71e62b9608d956dfc2a115ad70c8da` | 2026-01-10T02:19:48+08:00 | cyocyo10 | fix: 修复虎牙断流问题，使用 getCdnTokenInfoEx 和 buildAntiCode |
| `f801c5d167af00dbc5ac18eeaff770121c9dfe64` | 2026-03-27T22:39:51+08:00 | cyocyo | feat: 整合虎牙 getCdnTokenInfoEx 新链路 + 构建工作流 + 版本同步 |
| `5e5aa26273dd4f73ef07f722775ec54eb4ab7127` | 2026-03-27T22:45:57+08:00 | cyocyo | feat(master): 同步 master 剩余上游改动 |
| `3ba1f5390c8d175e720450d930df0bed74d37036` | 2026-03-29T00:07:54+08:00 | cyocyo | feat(douyin): 搜索 Cookie 隔离 + WebView 登录 + API 空安全 |
| `bad7dd22fc4bc895f3fdc0efab1abad97e886113` | 2026-03-29T00:07:59+08:00 | cyocyo | fix: 全面修复空安全、资源泄漏、逻辑错误 |
| `cfbcc5dacc36f6045fb4261e8beba47daeed2297` | 2026-03-29T00:26:28+08:00 | cyocyo | Merge branch 'master' into dev |
| `2c197ce30dbcad135da91ccfd31f442fb76df8e8` | 2026-03-29T00:43:34+08:00 | cyocyo | ci: 添加 push 自动构建（Android + Windows） |
| `018a4535ff55583167572d56781fea0d39b16629` | 2026-03-29T00:46:06+08:00 | cyocyo | fix: 修复 Log.e 参数类型错误导致编译失败 |
| `f390e482b08cdfb0ca40c4c749c48712427cbad3` | 2026-03-29T00:49:15+08:00 | cyocyo | Merge branch 'master' into dev |
| `6ce97494c5c5a4f02dcbda10de200d144105ba3d` | 2026-03-29T02:54:53+08:00 | cyocyo | feat: 回放状态区分+历史直播状态+Windows多窗口 |
| `1c9bfc99172706986425babf0120b73bfb2f5c1a` | 2026-03-29T03:26:40+08:00 | cyocyo | fix: 升级 desktop_multi_window 到 0.3.0 并适配新 API |
| `d76fff4635399ef8816977381b3de26a22162e4d` | 2026-03-29T03:32:53+08:00 | cyocyo | fix: HuyaSite/DouyinSite 补充 getLiveStatusDetail 实现 |
| `f2d9554e46042cac0123142f27f9ef2133ade6d3` | 2026-03-29T03:49:32+08:00 | cyocyo | chore: CI artifact 名称改为 android-apk/windows-msix |
| `3f38899429b0b9e0d99b4f4af06206e9fcd991f0` | 2026-03-29T03:53:18+08:00 | cyocyo | fix: 子窗口 Hive 文件锁冲突 + 版本号升级 1.12.0 |
| `38184b344c368c1d6c7d6608a8679e385383becc` | 2026-03-29T04:07:31+08:00 | cyocyo | fix: 子窗口 SmartDialog 未初始化崩溃 |
| `399ce2af7d6b42b3a0f47700c6023554d9b52fb7` | 2026-03-29T13:02:57+08:00 | cyocyo | fix: 按官方示例重构多窗口初始化，修复主窗口锁死 |
| `b70b9d9fb46b15026fc7b3314d517785ca56188e` | 2026-03-29T13:52:21+08:00 | cyocyo | fix: 子窗口排除 window_manager 注册，修复主窗口锁死 |
| `35063f51e313646c634a6635ccceb08cf2758680` | 2026-03-29T13:59:59+08:00 | cyocyo | fix: 修正子窗口 API 调用，WindowController 只用内置 show() |
| `53c8ff6be7b9917ff5e4f2ad695f10a45c6258bf` | 2026-03-29T14:13:59+08:00 | cyocyo | test: 子窗口零插件注册，验证是否为插件导致主窗口锁死 |
| `5d52f121177ea9c4a4060cf57261e09f40a45505` | 2026-03-29T14:42:25+08:00 | cyocyo | fix: 子窗口只注册 media_kit 视频插件，排除全部其他插件 |
| `310a70f7e767134a1eceba4e45b84812bc6c73e5` | 2026-03-29T18:48:18+08:00 | cyocyo | test: 只注册 media_kit_libs，排查哪个插件导致主窗口锁死 |
| `ca635dfddd7b86fa348f2f48791f947a9912419a` | 2026-03-29T19:01:16+08:00 | cyocyo | fix: PostMessage 延迟子窗口插件注册，彻底修复主窗口锁死 |
| `55f14088476ca23c83015072756cafb6b111e4bc` | 2026-03-29T19:30:34+08:00 | cyocyo | test: 只注册 connectivity_plus 一个插件，二分排查锁死原因 |
| `ba21885e049057790fe21bff3a28cd6289529e0f` | 2026-03-29T20:00:44+08:00 | cyocyo | fix: 修复 MediaKitVideoPlugin 静态单例导致主窗口锁死 |
| `12062535d3d1a6d33df46f37e26ad451d73cd0e6` | 2026-03-29T20:33:52+08:00 | cyocyo | fix: 简化子窗口插件注册——直接同步注册（参考 IPTV Player 方案） |
| `0db58658d344b1e2364f5292c1f0f08fa24361bb` | 2026-03-29T20:46:05+08:00 | cyocyo | fix: 多窗口改用多进程方案，彻底规避 MediaKitVideoPlugin 单例冲突 |
| `d87b6d35abc0334796c0ac8522f832b84f6c5817` | 2026-03-29T20:51:40+08:00 | cyocyo | fix: 修复 app_navigation.dart 缺少 sites.dart import |
| `da7d64337f387bd23dd2d8a3e5bc173585ef37cf` | 2026-03-29T21:20:26+08:00 | cyocyo | fix: 子窗口进程卡死——改用 detached 模式启动 |
| `252e06517638bc15e394c9634ca755549781070a` | 2026-03-29T22:08:25+08:00 | cyocyo | feat: 桌面端窗口内全屏 + 子窗口 ESC 退出全屏 |
| `110df2d03673c7290b786fb27a5f90fb5b684365` | 2026-03-29T22:20:15+08:00 | cyocyo | ci: 移除弃用的 timheuer/base64-to-file action |
| `5347a2dc9806d92b4b731bd1a92849ced7c7e807` | 2026-03-29T22:31:55+08:00 | cyocyo | ci: 启用 Node.js 24 消除弃用警告 |
| `d2af294869d52e9474607e35a30705b12af31062` | 2026-03-29T22:55:19+08:00 | cyocyo | feat: 静音切换按钮 + 子窗口关注同步 |
| `d5dfa5f99203aa70bcd03e5240cc188869288aeb` | 2026-03-29T23:07:13+08:00 | cyocyo | feat: 子窗口全数据同步（历史+屏蔽词+设置） |
| `0038ec96db7672811a355b0f09e8491b48482b78` | 2026-03-29T23:22:33+08:00 | cyocyo | fix: 桌面端启用 B站/抖音 WebView 登录 |
| `0b57359860666dac3b8526786af92e25114d8da2` | 2026-07-12T16:41:01+08:00 | cyocyo | fix: 修复 Windows 关注/历史无法持久化 |
| `081916002abebd33eec08dd822ac5750ec41afde` | 2026-09-25T15:10:55+00:00 | cyocyo | fix: 斗鱼取流签名重构(getEncryption+MD5) + 断流自动重取 + 斗鱼Cookie |
| `a69d96e46cf8eff2f1ab719a2bf505bb285a3112` | 2026-09-25T15:28:52+00:00 | cyocyo | ci: 固定 dynamic_color 1.8.1 修复 Android 构建 |
| `a20c1f4783fce08c1de7ac0fd9801f13a3c1df6d` | 2026-09-25T15:53:33+00:00 | cyocyo | fix: 修复 CI 构建失败 — Android 工具链对齐上游 + VS18 插件补丁 |
| `f985d591c690d8e81b1186f95173c6d34d3c8011` | 2026-09-25T16:10:41+00:00 | cyocyo | ci: 重新固定 dynamic_color 1.8.1 |
| `8d30a80fe97880f8d74fb281be1c244070578ea1` | 2026-09-25T16:45:51+00:00 | cyocyo | fix: 内置修复 auto_orientation_v2 2.4.6 缺失 kotlin-android 插件 |
| `0a3967e651c895d400e9535706d3daca9c505bb5` | 2026-09-25T16:58:58+00:00 | cyocyo | fix: Windows 编译改全局压制 STL1011,移除 inappwebview 内置补丁 |
| `e8de9121e9675149806320e3a94362e33dd2f330` | 2026-09-26T09:42:34+00:00 | cyocyo | feat: migrate AllLive desktop experience into Dart |
| `661fa6be79d04633db910d8cd239d171b0c2f867` | 2026-09-26T10:00:18+00:00 | cyocyo | ci: fail Windows validation on any unsuccessful check |
| `ed3b89341ee795b130d71b5f0018335cc3a81fc4` | 2026-09-26T10:22:42+00:00 | cyocyo | ci: migrate actions to Node 24 and pin the Android runner |
| `2fe794308e9d0050ba6b3187dc1e899f2004a55e` | 2026-09-26T10:56:04+00:00 | cyocyo | fix: repair Douyin login and responsive desktop playback controls |
| `1ea059dfaa0540d8d210a797c960fdbf8377cddd` | 2026-09-26T11:00:22+00:00 | cyocyo | feat: separate desktop playback menus from mobile sheets |
| `e972caafd35bf06cfd566fd9bf4981a10b12610a` | 2026-09-26T11:07:13+00:00 | cyocyo | fix: keep open desktop menu selections bound to their source |
| `cea785f13e0c541025ff86fd721ac5754e7e4c12` | 2026-09-26T11:29:21+00:00 | cyocyo | ci: build Windows portable and MSIX packages independently |
| `35732542efdfef56b46de13f84b29c3edbf157f8` | 2026-09-26T12:11:49+00:00 | cyocyo | perf: avoid full shared snapshot reads on idle desktop polls |
| `7233ab8c38076409c829e8f9304caa6b30419fa5` | 2026-09-26T12:13:41+00:00 | cyocyo | perf: show desktop startup and avoid duplicate child refreshes |
| `02669a464b4fb68aabf7d09f39e0513f9c8c3006` | 2026-09-26T12:26:35+00:00 | cyocyo | feat: complete desktop volume gestures and refine window controls |
| `e313d6d9e6c836212a802b70b1e8d62312c08462` | 2026-09-26T12:23:34+00:00 | cyocyo | fix: order viewing history by room open time and clarify rows |
| `5ab1f0b400c953cf9d5dfd2513e3eafb2f6e6ecf` | 2026-09-26T12:27:34+00:00 | cyocyo | fix: preserve responsive two-column viewing history |
| `55d2e1f43c4c9955fb99caf0d03d65d3bea3e481` | 2026-09-26T12:30:29+00:00 | cyocyo | test: verify integrated history layout and desktop interactions |
| `bb6e3be7ccf64d0b8a3a8911c369746346fbebf5` | 2026-09-26T12:39:00+00:00 | cyocyo | test: publish polling fixtures under the external writer lock |
| `2a1424bcf16524edafa95616e975fbcf692e7a3a` | 2026-09-26T12:45:47+00:00 | cyocyo | test: await synchronized state before checking backup recovery |
