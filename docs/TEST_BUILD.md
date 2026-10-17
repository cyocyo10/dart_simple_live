# 开发测试构建

本次先建立 develop 测试分支，保留 master/dev 与原修复分支，不重写历史。两项修复均集成在 1.14.3+11404：斗鱼 WS 短签名处理及恢复预算、阅读历史时消息缓存有界保留。

`.github/workflows/ci.yaml` 的 Development Build 在 develop push、目标为 develop 的 PR 和手动触发时运行。Android、Windows portable/MSIX 沿用已验证的构建步骤。分支构建使用现有签名身份，PR 构建不加载密钥且明确标记 unsigned。

测试包下载 Actions 的 android-apk；arm64-v8a 适合大多数近期 Android 手机。保留期 14 天。版本与签名不变不代表已通过真人验收，手机长时间直播及上翻消息仍需实机验证。

此次没有生产分支写入、标签或公开 Release。生产分支整理和晋级等待明确指令。
