import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/volume_scroll_region.dart';

Future<void> wheel(WidgetTester tester, Offset position, Offset delta) async {
  tester.binding.handlePointerEvent(PointerScrollEvent(
      position: position, scrollDelta: delta, kind: PointerDeviceKind.mouse));
  await tester.pump();
}

void main() {
  testWidgets('video scroll adjusts the hovered room without keyboard focus',
      (tester) async {
    final adjustments = [<double>[], <double>[]];
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      for (var i = 0; i < 2; i++)
        Expanded(
            child: VolumeScrollRegion(
          onAdjust: adjustments[i].add,
          child: SizedBox.expand(key: ValueKey(i)),
        )),
    ])));
    final left = tester.getCenter(find.byKey(const ValueKey(0)));
    final right = tester.getCenter(find.byKey(const ValueKey(1)));
    await wheel(tester, left, const Offset(0, -20));
    await wheel(tester, right, const Offset(0, 20));
    await wheel(tester, right, const Offset(20, 0));
    expect(adjustments, [
      [5],
      [-5]
    ]);
  });

  testWidgets('nested scrollable claims wheel without adjusting room volume',
      (tester) async {
    var adjustments = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: VolumeScrollRegion(
      onAdjust: (_) {
        adjustments++;
      },
      child: Stack(children: [
        SizedBox.expand(
            child: ListView.builder(
          controller: scroll,
          itemCount: 100,
          itemBuilder: (_, i) => Text('row $i'),
        )),
        const Positioned(
            left: 0,
            top: 0,
            width: 100,
            height: 100,
            child: AbsorbPointer(child: ColoredBox(color: Colors.black))),
      ]),
    )));
    await wheel(tester, const Offset(200, 200), const Offset(0, 50));
    expect(scroll.offset, greaterThan(0));
    expect(adjustments, 0);
  });
  testWidgets(
      'control overlay blocks video scrolling; disabled region ignores wheel',
      (tester) async {
    var adjustments = 0;
    await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
      VolumeScrollRegion(
        onAdjust: (_) {
          adjustments++;
        },
        child: const SizedBox.expand(),
      ),
      const Positioned(
          left: 0,
          top: 0,
          width: 100,
          height: 100,
          child: AbsorbPointer(child: ColoredBox(color: Colors.black))),
    ])));
    await wheel(tester, const Offset(50, 50), const Offset(0, 20));
    expect(adjustments, 0);
    await wheel(tester, const Offset(200, 200), const Offset(0, 20));
    expect(adjustments, 1);
    await tester.pumpWidget(MaterialApp(
        home: VolumeScrollRegion(
      enabled: false,
      onAdjust: (_) {
        adjustments++;
      },
      child: const SizedBox.expand(),
    )));
    await wheel(tester, const Offset(200, 200), const Offset(0, 20));
    expect(adjustments, 1);
  });
  testWidgets(
      'visible volume OSD cannot block repeated scrolling at its center',
      (tester) async {
    final adjustments = <double>[];
    await tester.pumpWidget(MaterialApp(
        home: Stack(children: [
      VolumeScrollRegion(
          onAdjust: adjustments.add, child: const SizedBox.expand()),
      const IgnorePointer(
          child: Center(
              child: ColoredBox(
                  color: Colors.black,
                  child: Padding(
                      padding: EdgeInsets.all(12), child: Text('音量 60%'))))),
    ])));
    final center = tester.getCenter(find.text('音量 60%'));
    await wheel(tester, center, const Offset(0, -20));
    await wheel(tester, center, const Offset(0, -20));
    expect(adjustments, [5, 5]);
  });
}
