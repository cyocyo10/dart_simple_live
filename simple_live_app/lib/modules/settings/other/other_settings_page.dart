import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/settings/other/other_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:url_launcher/url_launcher_string.dart';

class OtherSettingsPage extends GetView<OtherSettingsController> {
  const OtherSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("其他设置")),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          SettingsCard(
            child: Padding(
              padding: AppStyle.edgeInsetsA4,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: controller.exportConfig,
                      label: const Text("导出配置"),
                      icon: const Icon(Remix.export_line),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: controller.importConfig,
                      label: const Text("导入配置"),
                      icon: const Icon(Remix.import_line),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: controller.resetDefaultConfig,
                      label: const Text("重置配置"),
                      icon: const Icon(Remix.restart_line),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("账号", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => ListTile(
                    title: const Text("斗鱼 Cookie"),
                    subtitle: Text(
                      AppSettingsController.instance.douyuCookie.value.isEmpty
                          ? "未设置，登录后可观看原画高画质"
                          : "已设置",
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        editDouyuCookie(context);
                      },
                      child: const Text("设置"),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("播放器高级设置", style: Get.textTheme.titleSmall),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text.rich(
              TextSpan(
                text: "请勿随意修改以下设置，除非你知道自己在做什么。\n在修改以下设置前，你应该先查阅",
                children: [
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () {
                        launchUrlString(
                          "https://mpv.io/manual/stable/#video-output-drivers",
                        );
                      },
                      child: const Text(
                        "MPV的文档",
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsSwitch(
                    value:
                        AppSettingsController.instance.customPlayerOutput.value,
                    title: "自定义输出驱动与硬件加速",
                    onChanged: (e) {
                      AppSettingsController.instance.setCustomPlayerOutput(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu(
                    title: "视频输出驱动(--vo)",
                    value:
                        AppSettingsController.instance.videoOutputDriver.value,
                    valueMap: controller.videoOutputDrivers,
                    onChanged: (e) {
                      AppSettingsController.instance.setVideoOutputDriver(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu(
                    title: "音频输出驱动(--ao)",
                    value:
                        AppSettingsController.instance.audioOutputDriver.value,
                    valueMap: controller.audioOutputDrivers,
                    onChanged: (e) {
                      AppSettingsController.instance.setAudioOutputDriver(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu(
                    title: "硬件解码器(--hwdec)",
                    value: AppSettingsController
                        .instance.videoHardwareDecoder.value,
                    valueMap: controller.hardwareDecoder,
                    onChanged: (e) {
                      AppSettingsController.instance.setVideoHardwareDecoder(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text("日志记录", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsSwitch(
                    value: AppSettingsController.instance.logEnable.value,
                    title: "详细调试日志",
                    subtitle: "错误日志始终记录；开启后记录更多诊断信息。日志自动轮转并隐藏敏感字段",
                    onChanged: controller.setLogEnable,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: controller.exportDiagnostics,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text("导出诊断包"),
                ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  TextButton.icon(
                    onPressed: controller.openLogDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text("打开日志目录"),
                  ),
                TextButton.icon(
                  onPressed: controller.loadLogFiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text("刷新日志"),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: AppStyle.edgeInsetsL12,
            visualDensity: VisualDensity.compact,
            title: Text("日志列表", style: Get.textTheme.titleSmall),
            trailing: TextButton.icon(
              onPressed: () {
                controller.cleanLog();
              },
              label: const Text("清空日志"),
              icon: const Icon(Icons.clear_all),
            ),
          ),
          SettingsCard(
            child: SizedBox(
              height: 300,
              child: Obx(
                () => ListView.separated(
                  itemCount: controller.logFiles.length,
                  separatorBuilder: (context, index) => AppStyle.divider,
                  itemBuilder: (context, index) {
                    var item = controller.logFiles[index];
                    return ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: AppStyle.edgeInsetsL12.copyWith(right: 4),
                      title: Text(item.name),
                      subtitle: Text(Utils.parseFileSize(item.size)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!Platform.isLinux)
                            IconButton(
                              onPressed: () {
                                controller.shareLogFile(item);
                              },
                              icon: const Icon(Icons.share),
                            ),
                          IconButton(
                            onPressed: () {
                              controller.saveLogFile(item);
                            },
                            icon: const Icon(Icons.save),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑斗鱼账号 Cookie:粘贴浏览器登录后的整段 Cookie,留空保存即清除。
  void editDouyuCookie(BuildContext context) {
    var textController = TextEditingController(
      text: AppSettingsController.instance.douyuCookie.value,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("斗鱼 Cookie"),
          content: TextField(
            controller: textController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "浏览器登录 douyu.com 后，从开发者工具复制完整 Cookie",
              helperText: "关键字段为 acf_auth；留空保存可清除，恢复匿名取流",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppSettingsController.instance.setDouyuCookie("");
                Get.back();
              },
              child: const Text("清除"),
            ),
            TextButton(
              onPressed: () {
                Get.back();
              },
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () {
                AppSettingsController.instance.setDouyuCookie(
                  textController.text,
                );
                Get.back();
              },
              child: const Text("保存"),
            ),
          ],
        );
      },
    );
  }
}
