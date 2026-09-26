# Fork 维护建议与构建环境

本文件记录当前状态和建议，不代表已经更改 GitHub 默认分支、分支保护、发布渠道或自动同步设置。

## 来源与定位

- 原项目：[xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)。
- 本 fork：[cyocyo10/dart_simple_live](https://github.com/cyocyo10/dart_simple_live)。
- `origin` 指向本 fork，`upstream` 指向原项目，两个 remote 已配置。
- 当前方向：在 Dart 中保留 AllLive 的桌面体验，重点维护 Windows，同时验证 Android；其他客户端保留，但独立验证情况应单独说明。
- 保留仓库的 `LICENSE`、原作者版权及引用说明。复制其他项目的实现时记录源项目、源文件、提交与许可证；参考交互设计也应在说明中注明来源。
- README 建议明确标注“基于原项目的个人维护 fork”，分别链接原作者和本 fork 的问题反馈入口，列出新增功能与维护范围。现有“不提供 Release 安装包”的文案需要与自己的分发方式分别说明：CI Artifacts 是临时构建产物，正式 Release 是另一个渠道。

## 分支与上游更新

目前新迁移在 `dev`，GitHub 默认分支仍为 `master`。本地 `master` 保留旧提交 `59d0676`，远端 `origin/master` 为 `018a453`，两者已经分叉；调整稳定分支前先核对双方修改，不能直接重置覆盖。2026-09-26 按维护者要求仅整理当前维护的 `dev`：将历轮 56 条 fork 提交合并为一条，保留两条已合入的上游祖先线。详情见[工作记录](worklog/2026-09-26/README.md)。

建议保留简单分工：

- `dev`：日常集成，CI 必须通过。
- `master`：已经验收、准备发布的稳定代码。
- `feat/*`、`fix/*`、`sync/upstream-*`：短期分支，完成后合入并清理。

每月或遇到平台接口失效时检查上游。先检查工作区干净，再在专用分支尝试合并：

```bash
git fetch upstream
git switch -c sync/upstream-YYYYMMDD dev
git log --oneline --left-right dev...upstream/master
git merge --no-commit --no-ff upstream/master
```

解决冲突、检查差异并运行验证后再提交、合入 `dev`。只需要某个修复时可以在专用分支使用 `git cherry-pick -x <commit>`，保留源提交出处；整个分支合并与挑选提交应按实际差异选择，不同时机械执行。不要把“同步 fork”理解为强制让自己的开发分支等于上游。

通用的平台解析、重连、播放器 bug 可以整理成独立小提交，便于向上游贡献；AllLive 风格的字体预设、窗口交互等应与通用修复分开。提交或联系原作者需由维护者决定。

## 便于长期维护的最小文档

建议逐步补齐，避免一次重排整个项目：

- 根 README：fork 定位、上游来源、实际支持平台、下载与反馈入口。
- CHANGELOG：每个发布版本的变化、迁移提示和已知问题。
- CONTRIBUTING：本地环境、构建/测试命令、小范围提交和 PR 约定。
- 架构说明：`simple_live_core` 平台协议；app 服务层负责存储、同步、账号；页面只负责交互；桌面窗口与原生封装单独维护。
- AllLive 功能对照表：区分“已实现”“自动验证通过”“Windows 人工验收通过”。已有迁移说明见 [ALLLIVE_MIGRATION.md](ALLLIVE_MIGRATION.md)。
- 上游补丁记录：源版本、修改原因、回归测试、何时移除本地覆盖。`plugins/canvas_danmaku/PATCHES.md` 已采用这种方式，其他本地依赖也宜统一。

## 当前 Actions 升级

2026-09-26 已核对并在 7 份工作流中统一固定具体提交：

| Action | 版本 | 运行方式 |
| --- | --- | --- |
| actions/checkout | v7.0.1 | Node 24 |
| actions/setup-java | v6.0.1 | Node 24 |
| actions/upload-artifact | v7.0.1 | Node 24 |
| softprops/action-gh-release | v3.0.3 | Node 24 |
| subosito/flutter-action | v2 对应提交 `1a449444c387b1966244ae4d4f8c696479add0b2` | composite，内部使用 cache v5 |

`uses` 固定完整 SHA，旁边保留版本注释。后续升级应一起更新 SHA、版本注释和验证记录。旧的 `juliangruber/read-file-action` 已用读取 JSON 的 Python 步骤代替，保留 `content` 输出契约。

CI Android runner 固定为 `ubuntu-24.04`，避免 `ubuntu-latest` 自动迁移；原本固定的 Linux 发布环境 `ubuntu-22.04` 保持现状。移除了临时 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`，改用原生支持 Node 24 的 Action。

依据：[Node 20 退役公告](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)、[Ubuntu latest 迁移公告](https://github.com/actions/runner-images/issues/14748)。普通 `dev` push 只触发 CI；此次修改不会自行创建 tag 或发布 Release。未触发的 macOS、Linux、iOS、TV 发布链路不能算作已经完成运行验证。

## 发布与复现建议

- 后续把 Flutter 版本、应用依赖锁文件、Git 依赖提交一起纳入可复现构建策略。当前 app 忽略 `pubspec.lock`，本地曾使用特殊 SDK 环境解析依赖；应在正式 Flutter 环境重新生成并检查锁文件，再决定跟踪，不直接提交临时解析结果。
- 为自己的 fork 制定明确的版本号和构建号，并在下载页写明它与上游版本的关系。
- 主应用版本统一维护在 `simple_live_app/pubspec.yaml`，使用 `python3 tool/app_version.py --set 1.14.2+11403` 同步旧版 JSON 元数据，然后填写根 `CHANGELOG.md`。构建号必须递增；TV 与 core 的版本独立维护。
- 运行 `python3 tool/app_version.py` 检查一致性。主应用 CI 和发布工作流已加入此检查，`vX.Y.Z` / `dev_vX.Y.Z` 标签必须与应用版本一致。主应用工作流已移除硬编码分支，构建触发事件对应的提交；手动运行时以界面所选分支为准。
- 正式版本只从已验收提交创建 tag。旧 `assets/app_version.json` 当前未被主应用读取；保留并同步它，但它本身不证明已发布 Release。
- PR/提交执行分析、回归测试；正式版本增加 Windows 多窗口、登录、字体/DPI 和数据迁移人工验收。
- 更新依赖、合并上游、做功能迁移尽量分批提交，避免失败后难以定位。可后续启用 Dependabot 的 Actions 更新 PR，先人工审核，不自动合入。
- Release 附变更说明、校验和及对应源码/构建信息。保留可回退版本和用户数据兼容说明；普通运行日志不包含登录凭据。
