import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/log.dart';

class DebugLogPage extends StatelessWidget {
  const DebugLogPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("日志诊断"),
        actions: [
          IconButton(
            onPressed: () async {
              try {
                final logFile = await Log.exportDiagnostics();
                await SharePlus.instance.share(
                  ShareParams(files: [XFile(logFile.path)]),
                );
              } catch (error, stack) {
                Log.e('Unable to export diagnostics: $error', stack);
                SmartDialog.showToast("导出诊断包失败");
              }
            },
            icon: const Icon(Icons.save),
          ),
          IconButton(
            onPressed: () {
              Log.debugLogs.clear();
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: Obx(
        () => ListView.separated(
          itemCount: Log.debugLogs.length,
          separatorBuilder: (_, i) => const Divider(),
          padding: AppStyle.edgeInsetsA12,
          itemBuilder: (_, i) {
            var item = Log.debugLogs[i];
            return SelectableText(
              "${item.datetime.toString()}\r\n${item.content}",
              style: TextStyle(color: item.color, fontSize: 12),
            );
          },
        ),
      ),
    );
  }
}
