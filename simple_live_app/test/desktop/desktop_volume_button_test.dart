import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/live_room/player/live_room_keyboard.dart';
import 'package:simple_live_app/widgets/desktop_volume_button.dart';

void main() {
  testWidgets('single click opens persistent slider with explicit mute/restore',
      (tester) async {
    final volume = 50.0.obs;
    var saved = 50.0;
    var opened = 0;
    final savedValues = <double>[];
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: DesktopVolumeButton(
                    volume: volume,
                    onChangeEnd: savedValues.add,
                    onChanged: (value) => volume.value = value,
                    onMute: () {
                      if (volume.value > 0) {
                        saved = volume.value;
                        volume.value = 0;
                      } else {
                        volume.value = saved;
                      }
                    },
                    onOpened: () => opened++,
                    onClosed: () => closed++)))));
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(volume.value, 50); // Opening must not mute the room.
    expect(opened, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Slider), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(volume.value, greaterThan(50));
    expect(savedValues, [volume.value]);
    final beforeMute = volume.value;
    expect(find.text('音量 ${volume.value.round()}%'), findsOneWidget);
    await tester.tap(find.byTooltip('静音'));
    await tester.pumpAndSettle();
    expect(volume.value, 0);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byTooltip('取消静音'));
    await tester.pumpAndSettle();
    expect(volume.value, beforeMute);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(closed, 1);
  });

  testWidgets('volume popup fits a narrow window and Escape closes it',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shortcuts = <LiveRoomShortcut>[];
    await tester.pumpWidget(MaterialApp(
        home: LiveRoomKeyboard(
            onShortcut: (action) {
              shortcuts.add(action);
              return true;
            },
            child: Scaffold(
                body: Align(
                    alignment: Alignment.bottomRight,
                    child: DesktopVolumeButton(
                        volume: 50.0.obs,
                        onChanged: (_) {},
                        onMute: () {}))))));
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(Slider));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(320));
    expect(bounds.bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(shortcuts, isEmpty);
  });
  for (final brightness in Brightness.values) {
    testWidgets('volume menu fits Windows $brightness at large text size',
        (tester) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: AppStyle.themeFor(
            ColorScheme.fromSeed(
                seedColor: Colors.teal, brightness: brightness),
            platform: TargetPlatform.windows),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomRight,
                child: DesktopVolumeButton(
                    volume: 100.0.obs, onChanged: (_) {}, onMute: () {}))),
      ));
      await tester.tap(find.byTooltip('音量'));
      await tester.pumpAndSettle();
      expect(find.text('音量 100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(Slider));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(240));
    });
  }
}
