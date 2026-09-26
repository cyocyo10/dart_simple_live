import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:canvas_danmaku/static_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {} // Storage is exercised separately with real processes.
}

class _Room with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {}

void main() {
  testWidgets(
      'existing glyphs follow reactive size, weight, font and small-window changes',
      (tester) async {
    final settings = Get.put<AppSettingsController>(_Settings());
    settings.danmuSize.value = 25;
    settings.danmuFontFamily.value = 'Ahem';
    final room = _Room()..watchDanmakuSettings();
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
      width: 800,
      height: 400,
      child: DanmakuScreen(
        option: room.currentDanmakuOption,
        createdController: room.initDanmakuController,
      ),
    )));
    final renderer = room.danmakuController!;
    renderer.addDanmaku(DanmakuContentItem('AllLive 123'));
    renderer.addDanmaku(DanmakuContentItem('Top', type: DanmakuItemType.top));
    await tester.pump(const Duration(milliseconds: 16));
    final original = renderer.scrollDanmaku.single;
    final oldWidth = original.width;
    final oldImage = original.image;
    settings.danmuSize.value = 40;
    settings.danmuFontWeight.value = 9;
    settings.danmuFontFamily.value = 'serif';
    settings.danmuStrokeWidth.value = 3;
    await tester.pump(const Duration(milliseconds: 16));
    expect(renderer.option.fontSize, 40);
    expect(renderer.option.fontWeight, 8);
    expect(renderer.option.fontFamily, 'serif');
    expect(original.image, isNot(same(oldImage)));
    expect(original.width, greaterThan(oldWidth));
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter);
    expect(
        painters.whereType<ScrollDanmakuPainter>().single.fontFamily, 'serif');
    expect(
        painters.whereType<StaticDanmakuPainter>().single.fontFamily, 'serif');
    room.smallWindowState.value = true;
    await tester.pump(const Duration(milliseconds: 16));
    expect(renderer.option.fontSize, 20);
    expect(renderer.option.duration, 6);
    room.smallWindowState.value = false;
    await tester.pump(const Duration(milliseconds: 16));
    expect(renderer.option.fontSize, 40);
    expect(settings.danmuSize.value, 40);
    expect(tester.takeException(), isNull);
    room.disposeDanmakuController();
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });
}
