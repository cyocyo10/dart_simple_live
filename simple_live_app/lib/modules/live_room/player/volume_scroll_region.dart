import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Attach only to the video hit area, below controls and scrollable overlays.
/// The signal resolver lets a nested scrollable claim its own wheel events.
class VolumeScrollRegion extends StatelessWidget {
  const VolumeScrollRegion({
    super.key,
    required this.child,
    required this.onAdjust,
    this.enabled = true,
  });
  final Widget child;
  final ValueChanged<double> onAdjust;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (!enabled ||
              event is! PointerScrollEvent ||
              event.scrollDelta.dy == 0 ||
              event.scrollDelta.dx.abs() >= event.scrollDelta.dy.abs()) {
            return;
          }
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {
            onAdjust(event.scrollDelta.dy < 0 ? 5 : -5);
          });
        },
        child: child,
      );
}
