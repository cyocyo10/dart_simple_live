import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/live_room_keyboard.dart';

void main() {
  test('AllLive aliases select the same playback action', () {
    final aliases = <LiveRoomShortcut, List<LogicalKeyboardKey>>{
      LiveRoomShortcut.smallWindow: [
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.keyT
      ],
      LiveRoomShortcut.windowFull: [
        LogicalKeyboardKey.f12,
        LogicalKeyboardKey.keyW
      ],
      LiveRoomShortcut.fullscreen: [
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.enter
      ],
      LiveRoomShortcut.danmaku: [
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.keyD
      ],
      LiveRoomShortcut.screenshot: [LogicalKeyboardKey.f10],
      LiveRoomShortcut.volumeUp: [LogicalKeyboardKey.arrowUp],
      LiveRoomShortcut.volumeDown: [LogicalKeyboardKey.arrowDown],
    };
    for (final entry in aliases.entries) {
      for (final key in entry.value) {
        expect(liveRoomShortcutFor(key), entry.key);
      }
    }
    expect(liveRoomShortcutFor(LogicalKeyboardKey.keyA), isNull);
  });

  testWidgets('room keyboard skips editable focus and obscuring dialog',
      (tester) async {
    final actions = <LiveRoomShortcut>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LiveRoomKeyboard(
      onShortcut: (action) {
        actions.add(action);
        return true;
      },
      child: Scaffold(
          body: Column(children: [
        TextField(focusNode: focus),
        Builder(
            builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          const AlertDialog(content: Text('dialog'))),
                  child: const Text('open'),
                )),
      ])),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(actions, [LiveRoomShortcut.fullscreen]);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(actions, hasLength(1));
    focus.unfocus();
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    expect(actions, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(actions, hasLength(1));
  });
}
