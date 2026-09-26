# 历史构建参考

这里保存本 fork 在 `e022d01` 时的六份全平台/TV 构建文件，内容原样保留。它们继承自原项目，已包含此前的 Action 升级和 Windows 打包调整，因此不能把此快照当成未经修改的上游版本。

这些文件不在 `.github/workflows/` 中，GitHub Actions 不会触发它们。当前维护入口是根 `.github/workflows/ci.yaml`（Fork Build）和 `fork-release.yml`（Fork Release Draft），详见 [维护指南](../../FORK_MAINTENANCE.md)。

| 文件 | 归档时用途 |
| --- | --- |
| publish_app_dev.yaml | 主应用开发标签/手动全平台构建，上传 artifacts |
| publish_app_master.yaml | 手动全平台构建，上传 artifacts |
| publish_app_release.yml | 主应用正式标签，多平台 Release |
| publish_tv_app_dev.yaml | TV 开发标签，历史开发分支构建 |
| publish_tv_app_master.yaml | TV 手动 master 构建 |
| publish_tv_app_release.yaml | TV 标签发布 |

恢复某个平台时，把经过验证的必要步骤接入当前流程；不要直接复制整个目录回活动路径。尤其要检查旧文件中的分支硬编码、TOKEN secret、TV 更新地址、runner 和依赖版本，以及触发标签与实际源码提交是否相同。
