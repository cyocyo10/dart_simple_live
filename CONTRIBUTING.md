# 开发与验证

本 fork 的需求和问题讨论在 [cyocyo10/dart_simple_live](https://github.com/cyocyo10/dart_simple_live)。以 `dev` 为日常集成分支，短期分支使用 `feat/*`、`fix/*`；建议 PR 到 `dev`。稳定分支晋级及标签见 [维护指南](docs/FORK_MAINTENANCE.md)。

## 环境

使用 Flutter 3.38.x 稳定 SDK（使用其自带 Dart）、JDK 17。Windows 构建另需 Visual Studio C++ 桌面工具；Android 构建需 Android SDK。CI 的实际安装步骤见 `.github/workflows/ci.yaml`。依赖锁文件现状和特殊本地环境限制见维护指南，不把本机临时依赖覆盖带入提交。

在 `simple_live_app/` 中运行 `flutter pub get`。普通修改按影响范围选择验证；播放器、存储、迁移或跨模块变更应执行相关完整回归。CI 会执行下面的门禁，避免只测试当前平台的小路径。

## 主客户端验证

在 `simple_live_app/` 中运行：

```bash
flutter analyze --no-fatal-infos
flutter test
dart test/storage/shared_store_check.dart
dart test/storage/shared_store_polling_check.dart
dart test/diagnostics/diagnostic_writer_check.dart
dart test/migration/transfer_check.dart
dart tool/verify_login_session.dart
dart tool/verify_room_link_parser.dart
```

在 `simple_live_core/` 中运行：

```bash
dart pub get
dart test test/migration_core_offline_test.dart
```

这些入口使用离线 fixture、临时目录或测试进程；共享存储检查会真实启动多个进程。并行运行前确认输出目录和相关缓存不冲突。`simple_live_core` 还有依赖直播网站的其他测试，不应把它们自动当成稳定的离线门禁。

在仓库根目录检查版本：

```bash
python3 tool/app_version.py
```

工作流和发布脚本变更执行其 Python 测试及 `actionlint`；纯文档变更核对链接、命令与事实即可，不必为文字修改重复全套应用测试。

## 打包与人工验收

Windows 在 `simple_live_app/` 中执行：

```powershell
flutter build windows --release
./tool/windows/package-portable.ps1
./tool/windows/test-portable.ps1
```

CI 将 portable 与 MSIX 放在独立任务中。Android 正式构建需要维护者配置签名密钥；PR 构建明确标记为未签名，不能替代可安装升级包。签名文件、Cookie、账号数据库和诊断原始敏感日志不得提交。

桌面版本人工检查多窗口独立播放/关闭、主窗口退出后的数据保存、字体与 DPI、历史顺序/双列、登录和音量操作；自动测试不能替代这些观察。报告问题时提供系统、应用版本、复现步骤与脱敏诊断，避免附账号凭据。

## 提交与来源

每个提交围绕一项可解释的变更，写清问题、行为变化和有效验证。复制第三方代码保留许可与来源，移植上游补丁优先 `cherry-pick -x`。本地插件修改同步更新其补丁说明。历轮 AllLive 迁移已经一次性整合，后续按实际工作正常新增提交，不反复重写公开历史。
