# AllLive → Dart：历轮修改、验证和归档

## 目标与最终状态

以 AllLive 的桌面体验为迁移基线，Pure 仅作为参考，后续集中维护 Dart。主应用版本为 **1.14.1+11402**。功能说明见[迁移文档](../../ALLLIVE_MIGRATION.md)，版本记录见[CHANGELOG](../../../CHANGELOG.md)。

本记录汇总当前会话的实施与可从 Git 核实的历轮工作。早期会话没有完整对话或运行记录的部分，只按真实提交记录描述，不补造测试、耗时或结论。

## 历轮工作

| 阶段 | 已落地的内容 |
| --- | --- |
| 早期 fork 修改 | 虎牙取流、斗鱼签名和账号 Cookie；空安全与资源释放；Windows 多窗口探索；全屏、小窗和状态展示；Android/Windows 构建兼容。逐条见[压缩前 56 条提交](commits-before-squash.md)。 |
| 初次对照审查 | 检查 AllLive、Dart 与 Pure；识别独立窗口抢消费事件、设置覆盖、账号/弹幕不同步、字重及缓存渲染问题。见[初始审查快照](initial-audit.md)和[旧同步服务复现](initial-follow-sync-repro.dart)。这是实现前记录。 |
| AllLive 桌面体验迁移 | 独立直播窗口；带锁共享存储及备份恢复；共享收藏、历史、账号、设置与屏蔽词；弹幕字体、字号、字重、描边和小窗预设；快捷键及 JSON 互导。 |
| 登录、数据与播放修复 | 登录入口、扫码检测、取消/过期请求隔离；关注标签与数据导入事务；抖音官方登录入口；平台链接解析；播放请求归属、关闭与重连隔离。 |
| 桌面交互与性能 | 鼠标滚轮/左键上下拖动调音量；单击音量按钮显示滑块；桌面清晰度/线路菜单；短动画、系统字体与窄窗适配；先显示启动反馈，减少子窗口重复刷新和空闲完整快照读取。 |
| 历史排序与显示 | 以打开房间的时间排序，防止慢请求、重连和旧窗口置顶；常用宽度恢复双列，窄窗/大字号切换单列；头像、主播、状态和本地时间稳定对应。 |
| 工程与交付 | Windows 便携版单入口封装，与 MSIX 独立构建；诊断日志、版本一致性脚本；Actions Node 24 与固定 runner；保留来源、许可证和本地插件补丁说明。 |
| 本次整理 | 将 dev 的 56 条 fork 独有提交压成一条；归档完整工作记录；清理旧 CI；核实 AllLive 远端后删除本机原项目及构建缓存。 |

## 历史归属与压缩边界

- 压缩前 dev：`2a1424bcf16524edafa95616e975fbcf692e7a3a`。
- 已合入的上游 dev 边界：`fcadd0585a11fc95bac97f7addc65e8dad5ed638`。
- 已合入的上游 master 边界：`ef4cfc059ba7577b1d51f034a41b0cbeaaf349f0`。
- 两条上游线之间存在分叉。新提交直接使用上述两个原始提交为父节点，保留现有原作者及贡献者的 SHA、署名和祖先关系；不会把尚未合入的上游更新伪装成本地改动。
- 两个边界之后共有 56 条本 fork 提交（54 条普通提交、2 条 master 合并提交），全部整合为一条自有提交。
- 本次整理的最终文件相对压缩前仅新增/更新 `docs/` 下的工作记录。应用、资源、版本、测试和工作流内容均保持一致。
- 历史标签、其他分支及 upstream 引用保持原位。此操作整理当前维护分支 `dev`；不把已有发布标签重新指向新提交。

## 验证证据

已验证源码对应 Git tree：`828056faffeb817d2ebeb8225c45eb93c9a1a20e`，提交为压缩前 dev。

- 本地完整 Flutter 回归：91 项通过；静态分析 0 error、0 warning、42 条 info。
- [最终 Windows/Android CI](https://github.com/cyocyo10/dart_simple_live/actions/runs/36242951655)：三个任务均成功，均为 0 条 Actions annotations。
- Windows runner 再次执行并通过 91 项 Flutter 测试、核心离线测试、共享存储/轮询、诊断日志、JSON 互导、登录及链接解析检查。
- 共享存储覆盖 3 个真实进程的 75 次并发写入、主窗口退出后持久化、备份恢复、损坏及未来格式保护。
- Windows 轮询实测：3 个窗口、1 MB 快照、空闲约 3.4 秒完整读取 3 次；此前每 300 ms 全量轮询会调度 33 次。普通外部更新约 207 ms，同大小/同修改时间替换约 2691 ms 被强制校验发现。这些是存储测试数据，不是 GUI 帧率测试。
- Windows 启动器原生测试通过：目录结构、Unicode 路径与参数、运行目录、独立子进程、退出码。
- 实际产物检查：便携包根目录为 `Simple Live.exe`、`runtime/`、`使用说明.txt`，说明标记 `1.14.1+11402`；MSIX 清单为 `1.14.1.0`。

整理历史与文档时，按 Git tree 检查全部非文档文件与上述通过 CI 的版本一致；因此本次提交标记 `[skip ci]`，保留现有成功构建和可下载产物，避免为同一应用源码重复打包。[GitHub 的跳过构建规则](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)仅应用于本次提交，不关闭工作流。

### 中间失败与修复

- 部分本地测试曾遇到磁盘不足；清理本任务生成的旧构建缓存后重跑，最终完整测试通过。
- 历史组件测试的真实文件 I/O 需在 `tester.runAsync` 内执行，避免模拟时钟等待。
- Windows 轮询测试的夹具最初绕过文件锁，半写入内容可能触发备份恢复；改为独立 Dart 进程持锁发布。
- 随后的 Windows 回归发现固定 650 ms 不能保证所有窗口同步，旧缓存可能被误判成恢复结果；改为先等待所有活动读端到达新状态，再验证回退、损坏文件保留和未来格式保护。
- 修复后完整 Windows 验证通过。两条失败/取消构建 `36242143975`、`36242593573` 已清理，原始日志保存在本机私有归档。

## 构建历史与下载

清理前的记录见 [builds-before-cleanup.json](builds-before-cleanup.json)，删除清单见 [build-cleanup.json](build-cleanup.json)。清理 10 条旧的 CI Build 记录，保留当前成功构建 `36242951655` 和标签发布记录 `20861456182`；旧记录中的链接在删除后不再可访问。

- [Windows 便携版](https://github.com/cyocyo10/dart_simple_live/actions/runs/36242951655/artifacts/10906528724)
- [Windows MSIX](https://github.com/cyocyo10/dart_simple_live/actions/runs/36242951655/artifacts/10906682067)
- [Android APK](https://github.com/cyocyo10/dart_simple_live/actions/runs/36242951655/artifacts/10906298479)

## AllLive 原项目清理与恢复

已确认 [AllLive 远端 master](https://github.com/cyocyo10/AllLive/commit/c6951df959b7ead0d93edc087188788b49f1e273) 为 `c6951df959b7ead0d93edc087188788b49f1e273`，与本机最新源码一致。此前显示 ahead 6 是过期的本地远端引用；fetch 后为 0 ahead / 0 behind，无未提交业务源码。

清理原仓库、源码及构建缓存，释放约 485 MiB；完整备份和已有工作记录约 44 MiB。外层目录保留为工作区，Dart、Pure 及所有 Dart worktree 路径继续有效。详细删除清单和空间测量见 [alllive-cleanup.json](alllive-cleanup.json)。

本机私有归档位于仓库 `.local-archive/2026-09-26/`，由 `.git/info/exclude` 排除；签名证书和本机配置未上传 GitHub：

- `AllLive-complete.bundle`：AllLive 全部可达历史与 refs，可直接用 `git clone <bundle> <恢复目录>` 恢复。
- `dart-before-squash.bundle`：原 dev 历轮提交；需先有上述两个上游父节点，再用 `git fetch <bundle> refs/heads/dev:refs/heads/recovery/dev-before-squash` 恢复到独立分支。
- `AllLive-private/`：签名证书、本机 `.grok` 配置及原 Git 配置；复制后已比对 SHA-256。
- `raw-work-records/`：本轮已有日志、差异补丁、初始审查和复现材料。中途失败日志仅供追溯，以最终通过记录为准。
- `manifest.json`：上述归档文件的大小与 SHA-256。

## GitHub 代理与后续维护

本机直连 `github.com`、`api.github.com` 的连接测试超时，代理 `http://127.0.0.1:7890` 返回成功。Dart 的本地 Git 配置已固定 GitHub HTTPS 代理和 SSH URL 的 HTTPS 转换；GitHub CLI 通过仓库别名 `git gh …` 使用同一代理，例如 `git gh run list`。普通 `git push/pull` 已实际验证成功。此配置属于本机 `.git/config`。

后续开发仍按功能保留清晰的小提交；此次压缩是维护者要求的一次性历史整理。应用版本继续由 `tool/app_version.py` 管理，本次没有业务源码变化，不增加版本号。

## 尚需设备验证的范围

Windows 真人账号登录、真实平台播放、不同 DPI 的字体视觉和窗口开关手感，仍需实机验证。TV/Console、线上 WebDAV/远程同步没有完成完整端到端验收。没有足够证据宣称所有平台的全部需求或性能问题都已经解决。

代理角色按当时可用配置请求 explorer / sol_implementer / sol_complex；运行时模型、effort、完整耗时和用量无法可靠核验，不将配置当作实际运行统计。
