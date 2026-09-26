import 'package:flutter/material.dart';
import 'app_style.dart';

/// A visible first frame that does not depend on storage, accounts or GetX.
class DesktopStartupApp extends StatelessWidget {
  const DesktopStartupApp({
    super.key,
    this.liveWindow = false,
    this.failed = false,
    this.onClose,
  });

  final bool liveWindow;
  final bool failed;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppStyle.themeFor(AppColors.lightColorScheme),
        darkTheme: AppStyle.themeFor(AppColors.darkColorScheme),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (failed)
                      const Icon(Icons.error_outline_rounded, size: 40)
                    else
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      failed
                          ? '启动失败'
                          : (liveWindow ? '正在打开直播间' : '正在启动 Simple Live'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      failed ? '原有数据已保留。请查看应用数据目录中的日志。' : '正在准备播放器和共享设置…',
                      textAlign: TextAlign.center,
                    ),
                    if (failed && onClose != null) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: onClose, child: const Text('关闭窗口')),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
