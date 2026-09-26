import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'volume_scroll_region.dart';

/// The video hit area shared by normal, fullscreen and small-window controls.
/// Keep buttons, menus and scrollable overlays above this region in the stack.
class PlayerGestureRegion extends StatelessWidget {
  const PlayerGestureRegion({
    super.key,
    required this.controller,
    required this.child,
    this.onLongPress,
  });

  final PlayerController controller;
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final desktop = !Platform.isAndroid && !Platform.isIOS;
    return LayoutBuilder(
      builder: (context, constraints) => VolumeScrollRegion(
        enabled: desktop,
        onAdjust: controller.adjustRoomVolume,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.onTap,
          onDoubleTapDown: controller.onDoubleTap,
          onLongPress: onLongPress,
          // Once the recognizer accepts a drag, include its initial movement.
          // Flutter still arbitrates taps/drags and accepts only the left button.
          dragStartBehavior:
              desktop ? DragStartBehavior.down : DragStartBehavior.start,
          onVerticalDragStart: (details) => controller.onVerticalDragStart(
            details,
            viewportHeight: constraints.maxHeight,
          ),
          onVerticalDragUpdate: controller.onVerticalDragUpdate,
          onVerticalDragEnd: controller.onVerticalDragEnd,
          onVerticalDragCancel: controller.onVerticalDragCancel,
          child: child,
        ),
      ),
    );
  }
}
