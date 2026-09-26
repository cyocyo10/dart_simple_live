import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_gesture_region.dart';
import 'package:window_manager/window_manager.dart';

class FakeVolumePlayer extends Fake implements Player {
  final volumes = <double>[];
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
}

class GestureController extends PlayerController {
  final native = FakeVolumePlayer();
  int taps = 0;
  int doubleTaps = 0;
  @override
  Player get player => native;
  @override
  void onTap() => taps++;
  @override
  void onDoubleTap(TapDownDetails details) => doubleTaps++;
}

GestureController controller() {
  final result = GestureController();
  result.setRoomVolume(50, persistDefault: false);
  addTearDown(() => result.hidevolumeTimer?.cancel());
  return result;
}

Widget video(GestureController controller, {bool movable = false}) {
  Widget result = Stack(children: [
    Positioned.fill(
        child: PlayerGestureRegion(
            controller: controller, child: const SizedBox.expand())),
    Obx(() => IgnorePointer(
        child: Center(
            child: controller.showGestureTip.value
                ? Text(controller.gestureTipText.value)
                : const SizedBox.shrink()))),
  ]);
  if (movable) result = DragToMoveArea(child: result);
  return result;
}

void main() {
  testWidgets('mouse drag changes only its room and scales to video height',
      (tester) async {
    final left = controller();
    final right = controller();
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      Expanded(child: video(left)),
      Expanded(child: video(right)),
    ])));
    // Start near the top, outside the old middle-half restriction.
    final drag = await tester.startGesture(const Offset(200, 100),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(0, -48)); // 10% of 80% * 600px.
    await tester.pump();
    expect(left.playbackVolume.value, closeTo(60, 0.01));
    expect(left.native.volumes.last, closeTo(60, 0.01));
    expect(right.playbackVolume.value, 50);
    expect(find.text('音量 60%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(left.showGestureTip.value, isTrue); // Held still, OSD stays visible.
    await drag.moveBy(const Offset(0, 96));
    await tester.pump();
    expect(left.playbackVolume.value, closeTo(40, 0.01));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(left.verticalDragging, isFalse);
    expect(left.showGestureTip.value, isFalse);
    expect(left.taps, 0);
    expect(left.doubleTaps, 0);
  });

  testWidgets('small-window vertical drag wins over window pan; cancel resets',
      (tester) async {
    final room = controller();
    room.fullScreenState.value = true;
    room.smallWindowState.value = true;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 320, height: 200, child: video(room, movable: true)))));
    final drag = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(0, -16));
    await tester.pump();
    expect(room.playbackVolume.value, closeTo(60, 0.01));
    expect(tester.takeException(), isNull); // No native window-pan invocation.
    await drag.cancel();
    await tester.pump(const Duration(milliseconds: 50));
    expect(room.verticalDragging, isFalse);
    expect(room.showGestureTip.value, isFalse);
    room.onVerticalDragUpdate(DragUpdateDetails(
        globalPosition: Offset.zero, delta: const Offset(0, -100)));
    expect(room.playbackVolume.value, closeTo(60, 0.01));
  });

  testWidgets('volume clamps and reverses immediately at either boundary',
      (tester) async {
    final room = controller();
    await tester.pumpWidget(MaterialApp(home: video(room)));
    final drag = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(0, -480));
    await tester.pump();
    expect(room.playbackVolume.value, 100);
    await drag.moveBy(const Offset(0, 48));
    await tester.pump();
    expect(room.playbackVolume.value, closeTo(90, 0.01));
    await drag.moveBy(const Offset(0, 480));
    await tester.pump();
    expect(room.playbackVolume.value, 0);
    await drag.moveBy(const Offset(0, -48));
    await tester.pump();
    expect(room.playbackVolume.value, closeTo(10, 0.01));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('hover, right button and locked fullscreen do not change volume',
      (tester) async {
    final room = controller();
    await tester.pumpWidget(MaterialApp(home: video(room)));
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: const Offset(400, 300));
    await hover.moveTo(const Offset(400, 200));
    await hover.removePointer();
    final secondary = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await secondary.moveBy(const Offset(0, -100));
    await secondary.up();
    await tester.pump();
    expect(room.playbackVolume.value, 50);
    room.fullScreenState.value = true;
    room.lockControlsState.value = true;
    final locked = await tester.startGesture(const Offset(400, 300),
        kind: PointerDeviceKind.mouse);
    await locked.moveBy(const Offset(0, -100));
    await locked.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(room.playbackVolume.value, 50);
    expect(room.showGestureTip.value, isFalse);
  });

  testWidgets(
      'controls overlay consumes drag; click and double click still work',
      (tester) async {
    final room = controller();
    await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
      video(room),
      const Positioned(
          left: 0,
          top: 0,
          width: 100,
          height: 100,
          child: AbsorbPointer(child: ColoredBox(color: Colors.black))),
    ])));
    final blocked = await tester.startGesture(const Offset(50, 50),
        kind: PointerDeviceKind.mouse);
    await blocked.moveBy(const Offset(0, -48));
    await blocked.up();
    await tester.pump();
    expect(room.playbackVolume.value, 50);
    Future<void> click() async {
      final pointer = await tester.startGesture(const Offset(400, 300),
          kind: PointerDeviceKind.mouse);
      await pointer.up();
    }

    await click();
    await tester.pump(const Duration(milliseconds: 350));
    expect(room.taps, 1);
    await click();
    await tester.pump(const Duration(milliseconds: 100));
    await click();
    await tester.pump(const Duration(milliseconds: 350));
    expect(room.doubleTaps, 1);
    expect(room.playbackVolume.value, 50);
  });
}
