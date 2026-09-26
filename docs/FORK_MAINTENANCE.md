# 独立维护与发布

本仓库是 [cyocyo10/dart_simple_live](https://github.com/cyocyo10/dart_simple_live)。独立维护 AllLive 风格的 Dart 客户端；原项目 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) 作为上游来源，保留作者历史、版权与 `LICENSE`。GitHub 的 fork 关系保留，不代表需要跟随上游的版本、默认分支或发布节奏。

## 分支与仓库边界

| 名称 | 职责 | 更新方式 |
| --- | --- | --- |
| `origin/dev` | 本 fork 日常集成 | 小提交/短期分支合入，自动构建 |
| `origin/master` | 本 fork 稳定基线，默认分支 | 验收后从 dev fast-forward 晋级，自动构建 |
| `upstream/*` | 原作者的只读参考 | 手动 fetch，按需选择补丁 |
| `feat/*`、`fix/*`、`sync/upstream-*` | 临时实现或引入补丁 | 完成后合入 dev，清理自己的临时分支 |

2026-09-26 先将历轮 56 条 fork 提交整合为 `e022d01`，保留两个已经合入的上游父提交 `fcadd05`、`ef4cfc0`。旧的本地 master `59d0676` 与远端 master `018a453` 已分叉，不能直接合并回来，否则会重新带入已整理的旧提交链。本次整理完整备份两个旧 tip 后，将 master 一次性对齐已验证的迁移基线；此后恢复正常 fast-forward。旧虎牙请求模型及 `getCdnTokenInfoEx` 链路已保留，原始 master 仍可从备份恢复。详情见[分支整理记录](worklog/2026-09-26/fork-management.md)。

这里的稳定基线表示已完成对应自动验证；Windows 真人登录、DPI 与流畅度的验收状态需另行记录。不得将 master 上的任何提交都自动宣传成已正式发布。

本机已配置 `origin` 默认推送、GitHub CLI 默认仓库为自己的 fork，并为 `upstream` 设置不可用的 push URL，减少误推。新机器可在确认 remote 后设置：

```bash
git remote -v
git config --local remote.pushDefault origin
git remote set-url --push upstream disabled://upstream-read-only
gh repo set-default cyocyo10/dart_simple_live
```

这些是本机配置，不随 clone 复制，也不是服务端权限隔离。GitHub 命令仍要明确目标仓库：多数子命令可用 `-R cyocyo10/dart_simple_live`，`gh repo view/edit` 则直接传仓库名。不要以 CLI 自动猜测结果作为目标仓库的依据。

## 其他电脑上的旧 clone

本次一次性重排历史后，旧 clone 不宜直接 pull/merge 旧 dev 或 master 来“消除分叉”。先保存未提交文件，再检查旧分支是否含有尚未迁入的新工作；以下方式保留原分支全部提交，不做 reset。仅适用于本地 dev/master 都存在、工作区干净且归档名尚未使用的情况：

```bash
git status
git fetch origin
git branch -m dev archive/dev-before-layout
git branch -m master archive/master-before-layout
git switch -c dev --track origin/dev
git branch --track master origin/master
```

有额外本地修改时，在归档分支与新 dev 对比后只移植缺少的修改。若已完成迁移或分支名不同，不重复机械执行这些命令。其他 worktree 正在使用相应分支时也应先检查工作目录与分支关系。

## 日常开发与 master 晋级

在 dev 或自己的短期分支开发，提交与推送后检查对应 SHA 的 **Fork Build**。分支构建、手动构建和标签构建复用同一套 Android / Windows 步骤。

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
# 完成修改、相关验证与提交
git push origin dev
```

准备晋级时，先确认目标 dev 提交的 CI 成功，并完成此次行为变更所需的人工验收。在干净工作区执行：

```bash
git fetch origin
git switch master
git pull --ff-only origin master
git merge --ff-only origin/dev
git push origin master
git switch dev
```

如果 fast-forward 被拒绝，先检查分叉原因；不要直接加 `--force`。hotfix 最好从 dev 实现并晋级；确需从 master 紧急修复时，修复完成立即把 master 合回 dev，再恢复上述流程。原作者的分支不会参与这个晋级步骤。

## 构建与下载

活动工作流只有两个：

| 工作流 | 触发 | 结果 |
| --- | --- | --- |
| **Fork Build** / `ci.yaml` | dev/master push、PR，或 Run workflow 选择分支 | `android-apk`、`windows-portable`、`windows-msix` |
| **Fork Release Draft** / `fork-release.yml` | `vX.Y.Z`、`dev_vX.Y.Z` 标签 | 校验来源和版本，复用构建，生成带清单和校验和的 Release 草稿 |

查看 [master 构建](https://github.com/cyocyo10/dart_simple_live/actions/workflows/ci.yaml?query=branch%3Amaster) 或 [dev 构建](https://github.com/cyocyo10/dart_simple_live/actions/workflows/ci.yaml?query=branch%3Adev)。两种 Windows 包使用独立任务，一种失败不取消另一种；整体成功要求三个构建均通过。公共 Flutter/存储/迁移检查在 portable 任务中运行。

Android 的分支和标签构建需要 `KEYSTORE_BASE64`、`STORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS` 四项仓库 secrets；PR 不加载签名密钥，产物明确标记为 unsigned，不能当作正式升级包。现有安装标识和签名身份不因分支整理而更改。

六份继承的全平台/TV 工作流移到 [参考目录](reference/workflows/README.md)，保留完整内容但不被 Actions 触发。macOS、Linux、iOS 和 TV 源码仍保留；未来验证后再将其接入自己的统一构建。TV 版本与更新入口仍是历史实现，未纳入本 fork 当前正式发布范围。

Action 固定完整 SHA；Android 使用 Ubuntu 24.04，Flutter 使用 3.38.x。升级 action 时核对上游官方版本和对应 SHA。当前 app 未跟踪 `pubspec.lock`；必须在标准 Flutter 环境解析并检查后再决定纳入，不能把本机特殊 SDK 的临时解析/覆盖结果提交。既有成功构建证明当时解析可用，不等同于所有依赖已经完全锁定。

## 自己的版本和 Release

版本沿用本 fork 的 `1.14.x` 系列，与原作者 `1.11.x` 的节奏无关，不按上游版本自动覆盖。`simple_live_app/pubspec.yaml` 是主应用版本来源；`assets/app_version.json` 保持一致，下载地址指向本 fork。当前主应用并未消费这份旧 JSON，修改它本身不会形成线上更新发布。

产品变更用脚本同步版本、递增 BUILD，填写 `CHANGELOG.md`：

```bash
python3 tool/app_version.py --set 1.14.2+11403
python3 tool/app_version.py
```

仅文档、构建编排和维护规则的修改不改变应用版本。Windows 版本字段限制由脚本检查；MSIX 的映射须以实际包 manifest 为准，不假定构建号一定进入其第四段。

- `vX.Y.Z`：源码版本必须为 X.Y.Z，提交必须属于 master 历史，生成正式版本的 **草稿**。
- `dev_vX.Y.Z`：同样匹配版本，提交必须属于 dev 历史，生成预发布 **草稿**。
- 日常 dev 包直接使用 Actions artifacts，通常不需要每次创建开发标签。

从对应分支成功的 Fork Build 复制完整源码 SHA，再在该提交创建新标签。例如未来准备发布 1.14.2 时，先把下面的 `VERIFIED_COMMIT_SHA` 替换为实际已验收 SHA：

```bash
git switch --detach VERIFIED_COMMIT_SHA
python3 tool/app_version.py --tag v1.14.2
git tag -a v1.14.2 -m 'Simple Live fork 1.14.2'
git push origin v1.14.2
git switch dev
```

推标签前确认实际 checkout 的提交已晋级 master。文档归档提交可能带 `[skip ci]`；发布标签应指向前述已验收源码提交，避免跳过 push 触发的发布流水线（[GitHub 说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)）。标签不得移动复用；失败时从同一个运行重试。工作流核对仓库身份、tag、版本和分支祖先，再构建全部平台；使用内置 `GITHUB_TOKEN` 创建草稿，不依赖旧的 `TOKEN` secret。草稿包含 Windows ZIP/MSIX、APK、源码提交信息和 SHA256 清单。检查变更说明、产物与人工验收后，由维护者在 Releases 公开发布。普通 push 和本轮整理不会自动创建公开 Release。

## 按需借鉴上游

先在专用分支检查变化，再选择需要的修复：

```bash
git fetch upstream
git switch -c sync/upstream-YYYYMMDD dev
git log --oneline --left-right dev...upstream/dev
# 阅读目标提交和涉及的本地差异后，仅移植需要的提交
git cherry-pick -x <upstream-commit>
```

冲突按本 fork 的产品行为解决；验证后合入 dev。只有明确需要整批更新时才 merge 上游，先审查对共享存储、多窗口、登录和本地插件补丁的影响。不要直接点击让自己分支等于上游的覆盖操作。来源记录至少包括原仓库、提交/文件、原因和本地验证；可通用的 bug 修复保持小提交，是否向原作者提交 PR 由维护者决定。

AllLive 已通过远端和私有完整 bundle 保存，本机旧工作目录已清理。Pure 保留为参考，目前仍是完整 checkout；如需进一步节省空间，可保留固定提交的源码压缩包、来源 SHA 与许可证，再删除可重新 clone 的 Git 历史。不要将参考仓库整体复制进本项目的 Git 历史。

## 网络与工作记录

本机直连 GitHub 曾超时，已按维护者授权配置仓库级 `http.https://github.com/.proxy=http://127.0.0.1:7890`，并将 GitHub SSH URL 映射到 HTTPS。Git 正常使用 `git fetch/push`；CLI 使用 `git gh ... -R cyocyo10/dart_simple_live`，别名从仓库配置读取代理。这不影响应用自己的直播网络，也不把本机代理写入 CI。

公开结论与复现步骤放在 `docs/worklog/`。完整历史备份、原始执行日志及私有配置位于 `.local-archive/2026-09-26/`，通过本机 `.git/info/exclude` 排除；不要上传整个目录。清理构建保留当前可用包和必要记录。

项目 [AGENTS.md](../AGENTS.md) 按 Astra 主会话组织，保留用户指定的 Luna/Sol 执行角色和单写入者约束。它是项目指引，不修改客户端模型配置。编写依据是 OpenAI 的 [AGENTS.md 加载说明](https://learn.chatgpt.com/docs/agent-configuration/agents-md) 与 [Astra 指令整理建议](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)：把必需边界写清，按任务读取文档，避免重复铺陈和无关检查。
