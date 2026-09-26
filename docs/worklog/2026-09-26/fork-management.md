# 独立维护流程整理 — 2026-09-26

## 需求与边界

维护者要求自己的 fork 与原作者分开管理，建立 dev/master 路径，并按 Astra 主会话重写项目 AGENTS.md。本次整理不修改应用行为、安装标识、账号或数据格式，版本保持 `1.14.1+11402`。不创建新 tag、不公开发布 Release。

## 已整理内容

- 首页明确 `cyocyo10` 维护版、独立 Issues、下载渠道与支持范围，保留原作者来源与许可证。
- 新增项目 AGENTS.md 和 CONTRIBUTING.md，重写维护指南；AGENTS 继承用户全局规范，明确 Astra 主会话、四种执行角色、最多三个子代理、单目录单写入者和实际验收边界。未修改用户模型配置。
- 本机 GitHub CLI 原先自动选择 upstream，现固定自己的 fork；默认推送 origin，upstream 配置不可用 push URL。本机已有 GitHub 7890 代理继续使用，不写入应用或 CI。
- GitHub 默认分支保持 master；启用本 fork Issues，模板移除原作者自动指派，增加 master/dev 下载来源与脱敏诊断提示。
- Fork Build 同时服务 dev/master/PR/手动及可复用构建，独立生成 Android、Windows portable 和 MSIX。PR 未签名包明确标记，普通分支/tag 缺正式签名配置则失败。
- 六份历史全平台/TV 工作流原样移至 docs/reference/workflows；活动发布入口改为 Fork Release Draft，标签校验通过并且全部构建成功后才生成草稿，附提交信息与校验和，不自动公开发布。

## master 整理与恢复

整理前：

| 引用 | 提交 |
| --- | --- |
| dev / origin/dev | `e022d011a0ea6dc4dc75262fa036c4a0ff24327d` |
| 本地 master | `59d067689accf08ae87c012be3c1be891b75ad2d` |
| origin/master | `018a4535ff55583167572d56781fea0d39b16629` |

本地与远端旧 master 已分叉。当前 dev 是对旧开发历史的归并结果，应用目录与归并前 `2a1424b` 完全一致；该提交已通过 Windows/Android CI，见[成功构建 36242951655](https://github.com/cyocyo10/dart_simple_live/actions/runs/36242951655)。复核本地旧 master 新增的三个虎牙请求模型和 token 链路均已保留；模型差异是 import/格式调整。

旧 master 两个 tip 由本机 `refs/archive/fork-layout-20260926/{local-master,origin-master}` 保留，另保存完整、无前置依赖的 bundle：

- `.local-archive/2026-09-26/dart-master-before-layout.bundle`
- SHA256：`b3daa5750742ea573e21fe40b786ecfe921739bd023684d3078d913c17696850`
- `git bundle verify` 已通过；完整 bundle 的清单也加入本地 manifest.json。

本次使用针对旧 origin/master SHA 的 force-with-lease 进行一次性对齐；dev 正常 fast-forward。其目的为让稳定分支采用已经归并并验收的代码历史，不把旧 fork 提交链重新合回 dev。今后按维护指南 fast-forward 晋级，不继续常态化 force push。新维护配置与已验收业务代码一同在 dev/master 执行 CI，构建结果另行补充。

恢复旧内容时先查看/建立临时分支，不直接覆盖当前 master：

```bash
git bundle verify .local-archive/2026-09-26/dart-master-before-layout.bundle
git fetch .local-archive/2026-09-26/dart-master-before-layout.bundle refs/archive/fork-layout-20260926/origin-master:refs/heads/restore/old-master
```

## 代理与验证记录

- 一名 explorer 只读检查工作流/版本边界；一名 sol_complex 在独立 worktree 实现构建编排和发布验证脚本。主会话是主工作目录唯一写入者，负责文档、仓库设置、整合与验收。
- 使用配置角色 explorer（Luna High）和 sol_complex（Sol High）；工具未返回可独立验证的实际运行模型、effort 或 token 用量，这些字段记为未知，不把角色声明当成运行遥测。
- 子代理完成 18 项 Python 测试与 actionlint 1.7.12 校验；主会话对整合结果再次做必要验证并检查 GitHub 实际运行。没有为纯文档修改重复创建应用业务测试。
- 标签创建草稿路径未通过真实新 tag 发布演练，避免为测试创建伪版本；守卫、产物收集和校验和由脚本测试覆盖。Windows 真人登录、DPI、流畅度仍沿用迁移说明中的人工验收限制。
