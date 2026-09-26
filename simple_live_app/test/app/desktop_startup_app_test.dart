import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/desktop_startup_app.dart';

void main() {
  testWidgets(
    'startup is visible without initialized storage or account services',
    (tester) async {
      await tester.pumpWidget(const DesktopStartupApp(liveWindow: true));
      expect(find.text('正在打开直播间'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('startup failure fits a small window with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var closed = false;
    await tester.pumpWidget(
        DesktopStartupApp(failed: true, onClose: () => closed = true));
    await tester.ensureVisible(find.text('关闭窗口'));
    await tester.tap(find.text('关闭窗口'));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed initialization shows retained-data message and close action',
    (tester) async {
      var closed = false;
      await tester.pumpWidget(
        DesktopStartupApp(failed: true, onClose: () => closed = true),
      );
      expect(find.text('启动失败'), findsOneWidget);
      expect(find.text('原有数据已保留。请查看应用数据目录中的日志。'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('关闭窗口'));
      expect(closed, isTrue);
    },
  );
}
