import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

enum LiveRoomShortcut {
  volumeUp,
  volumeDown,
  smallWindow,
  windowFull,
  fullscreen,
  screenshot,
  danmaku,
  escape,
}

LiveRoomShortcut? liveRoomShortcutFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return LiveRoomShortcut.volumeUp;
  if (key == LogicalKeyboardKey.arrowDown) return LiveRoomShortcut.volumeDown;
  if (key == LogicalKeyboardKey.f8 || key == LogicalKeyboardKey.keyT)
    return LiveRoomShortcut.smallWindow;
  if (key == LogicalKeyboardKey.f12 || key == LogicalKeyboardKey.keyW)
    return LiveRoomShortcut.windowFull;
  if (key == LogicalKeyboardKey.f11 ||
      key == LogicalKeyboardKey.keyF ||
      key == LogicalKeyboardKey.enter) return LiveRoomShortcut.fullscreen;
  if (key == LogicalKeyboardKey.f10) return LiveRoomShortcut.screenshot;
  if (key == LogicalKeyboardKey.f9 || key == LogicalKeyboardKey.keyD)
    return LiveRoomShortcut.danmaku;
  if (key == LogicalKeyboardKey.escape) return LiveRoomShortcut.escape;
  return null;
}

/// One handler per visible room route; neither text input nor dialogs are intercepted.
class LiveRoomKeyboard extends StatefulWidget {
  final Widget child;
  final bool Function(LiveRoomShortcut action) onShortcut;
  const LiveRoomKeyboard(
      {required this.child, required this.onShortcut, super.key});
  @override
  State<LiveRoomKeyboard> createState() => _LiveRoomKeyboardState();
}

class _LiveRoomKeyboardState extends State<LiveRoomKeyboard> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || (event is! KeyDownEvent && event is! KeyRepeatEvent))
      return false;
    if (ModalRoute.of(context)?.isCurrent == false || SmartDialog.checkExist())
      return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null)
      return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) return false;
    final action = liveRoomShortcutFor(event.logicalKey);
    if (action == null) return false;
    if (event is KeyRepeatEvent &&
        action != LiveRoomShortcut.volumeUp &&
        action != LiveRoomShortcut.volumeDown) return true;
    return widget.onShortcut(action);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
