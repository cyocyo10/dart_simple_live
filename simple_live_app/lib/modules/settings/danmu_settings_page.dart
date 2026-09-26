import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/modules/live_room/player/danmaku_style.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class DanmuSettingsPage extends StatelessWidget {
  const DanmuSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("弹幕设置")),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: const [DanmuSettingsView()],
      ),
    );
  }
}

class DanmuSettingsView extends GetView<AppSettingsController> {
  final Function()? onTapDanmuShield;
  final DanmakuController? danmakuController;
  const DanmuSettingsView({
    this.onTapDanmuShield,
    this.danmakuController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
          child: Text("弹幕屏蔽", style: Get.textTheme.titleSmall),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "关键词屏蔽",
                onTap: onTapDanmuShield ??
                    () => Get.toNamed(RoutePath.kSettingsDanmuShield),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
          child: Text("弹幕设置", style: Get.textTheme.titleSmall),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "恢复 AllLive 弹幕风格",
                onTap: controller.restoreAllLiveDanmuStyle,
              ),
              AppStyle.divider,
              Obx(
                () => ListTile(
                  title: const Text("弹幕字体"),
                  subtitle: Text(
                    controller.danmuFontFamily.value.isEmpty
                        ? "系统默认"
                        : controller.danmuFontFamily.value,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showFontPicker(context),
                ),
              ),
              AppStyle.divider,
              Obx(() {
                final style = TextStyle(
                  fontSize: controller.danmuSize.value,
                  fontWeight: FontWeight.values[DanmakuStyle.fontWeightIndex(
                      controller.danmuFontWeight.value)],
                  fontFamily: controller.danmuFontFamily.value.isEmpty
                      ? null
                      : controller.danmuFontFamily.value,
                );
                return Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey.shade900,
                  child: Opacity(
                    opacity: controller.danmuOpacity.value
                        .clamp(0.1, 1.0)
                        .toDouble(),
                    child: Stack(children: [
                      Text("弹幕预览 AllLive 123",
                          style: style.copyWith(
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth =
                                    controller.danmuStrokeWidth.value
                                ..color = Colors.black)),
                      Text("弹幕预览 AllLive 123",
                          style: style.copyWith(color: Colors.white)),
                    ]),
                  ),
                );
              }),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text("字号、字体、粗细和描边会实时应用到播放弹幕；小窗字号减半。"),
              ),
              Obx(
                () => SettingsSwitch(
                  title: "默认开关",
                  value: controller.danmuEnable.value,
                  onChanged: (e) {
                    controller.setDanmuEnable(e);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "显示区域",
                  value: (controller.danmuArea.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setDanmuArea(e / 100.0);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "不透明度",
                  value: (controller.danmuOpacity.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setDanmuOpacity(e / 100.0);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体大小",
                  value: controller.danmuSize.toInt(),
                  min: 8,
                  max: 72,
                  onChanged: (e) {
                    controller.setDanmuSize(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体粗细",
                  value: controller.danmuFontWeight.value,
                  min: 1,
                  max: 9,
                  step: 1,
                  displayValue: [
                    "极细",
                    "很细",
                    "细",
                    "正常",
                    "小粗",
                    "偏粗",
                    "粗",
                    "很粗",
                    "极粗",
                  ][controller.danmuFontWeight.value - 1]
                      .toString(),
                  onChanged: (e) {
                    controller.setDanmuFontWeight(e);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "滚动速度",
                  subtitle: "弹幕持续时间(秒)，越小速度越快",
                  value: controller.danmuSpeed.toInt(),
                  min: 4,
                  max: 20,
                  onChanged: (e) {
                    controller.setDanmuSpeed(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体描边",
                  value: controller.danmuStrokeWidth.toInt(),
                  min: 0,
                  max: 5,
                  onChanged: (e) =>
                      controller.setDanmuStrokeWidth(e.toDouble()),
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "顶部边距",
                  subtitle: "曲面屏显示不全可设置此选项",
                  value: controller.danmuTopMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setDanmuTopMargin(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "底部边距",
                  subtitle: "曲面屏显示不全可设置此选项",
                  value: controller.danmuBottomMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setDanmuBottomMargin(e.toDouble());
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void showFontPicker(BuildContext context) {
    final input = TextEditingController(text: controller.danmuFontFamily.value);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("弹幕字体"),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "留空使用系统默认，如 Microsoft YaHei",
            helperText: "使用本机已安装的字体；缺失时使用系统替代字体。",
            helperMaxLines: 3,
          ),
          onSubmitted: (value) {
            controller.setDanmuFontFamily(value);
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              controller.setDanmuFontFamily(input.text);
              Navigator.of(context).pop();
            },
            child: const Text("应用"),
          ),
        ],
      ),
    ).whenComplete(input.dispose);
  }
}
