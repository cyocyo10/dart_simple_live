import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/platform_choice_button.dart';
import 'package:simple_live_app/widgets/desktop_settings_panel.dart';
import 'package:simple_live_app/widgets/desktop_control_bar.dart';

void main() {
  testWidgets('narrow Windows menu marks current choice and changes once',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <int>[];
    var closes = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
            body: PlatformChoiceButton(
                label: '清晰度',
                options: const ['高清', '原画'],
                selectedIndex: 0,
                onSelected: changes.add,
                onMobilePressed: () => fail('mobile'),
                onClosed: () => closes++))));
    await tester.tap(find.text('清晰度'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckedPopupMenuItem<int>>(
                find.byType(CheckedPopupMenuItem<int>).first)
            .checked,
        isTrue);
    await tester.tap(find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 0));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(find.text('清晰度'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
        (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 1));
    await tester.pumpAndSettle();
    expect(changes, [1]);
    await tester.tap(find.text('清晰度'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('原画'), findsNothing);
    expect(closes, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open menu preserves the options and callback it displayed',
      (tester) async {
    var choices = ['高清', '原画'];
    final selected = <String>[];
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        final snapshot = choices.toList();
        return Scaffold(
          body: PlatformChoiceButton(
            label: '清晰度',
            options: snapshot,
            selectedIndex: 0,
            onMobilePressed: () => fail('mobile'),
            onSelected: (index) {
              if (choices.contains(snapshot[index])) {
                selected.add(snapshot[index]);
              }
            },
          ),
        );
      }),
    ));
    await tester.tap(find.text('清晰度'));
    await tester.pumpAndSettle();
    rebuild(() => choices = ['流畅', '高清']);
    await tester.pump();
    await tester.tap(find.ancestor(
        of: find.text('原画'), matching: find.byType(CheckedPopupMenuItem<int>)));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.tap(find.text('清晰度'));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
        of: find.text('高清'), matching: find.byType(CheckedPopupMenuItem<int>)));
    await tester.pumpAndSettle();
    expect(selected, ['高清']);
  });

  testWidgets('narrow desktop bar can reach commands without overflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
            body: SizedBox(
                width: 280,
                height: 48,
                child: DesktopControlBar(
                    child: Row(children: [
                  for (var i = 0; i < 6; i++)
                    IconButton(
                        onPressed: () {}, icon: const Icon(Icons.settings)),
                  const Expanded(child: SizedBox()),
                  const Text('清晰度'),
                  const Text('线路'),
                  IconButton(
                      onPressed: () {}, icon: const Icon(Icons.fullscreen)),
                ]))))));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(-500, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byIcon(Icons.fullscreen)).dx, lessThan(280));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android uses existing sheet callback', (tester) async {
    var mobileCalls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
            body: PlatformChoiceButton(
                label: '线路',
                options: const ['线路1'],
                selectedIndex: 0,
                onSelected: (_) => fail('desktop'),
                onMobilePressed: () => mobileCalls++))));
    await tester.tap(find.text('线路'));
    expect(mobileCalls, 1);
    expect(find.byType(PopupMenuButton<int>), findsNothing);
  });

  testWidgets(
      'empty desktop choices are disabled and panel fits small viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
            body: Center(
                child: DesktopSettingsPanel(
                    title: '设置',
                    onClose: () {},
                    child: ListView(children: [
                      PlatformChoiceButton(
                          label: '清晰度',
                          options: const [],
                          selectedIndex: -1,
                          onSelected: (_) => fail('empty'),
                          onMobilePressed: () {})
                    ]))))));
    expect(
        tester
            .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
            .enabled,
        isFalse);
    expect(tester.getSize(find.byType(DesktopSettingsPanel)).height,
        lessThan(192));
    expect(tester.takeException(), isNull);
  });
}
