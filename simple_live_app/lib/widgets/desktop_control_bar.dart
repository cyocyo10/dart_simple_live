import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:simple_live_app/widgets/platform_choice_button.dart';

/// Keeps all player commands reachable when a desktop window is narrow.
class DesktopControlBar extends StatefulWidget {
  const DesktopControlBar({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopControlBar> createState() => _DesktopControlBarState();
}

class _DesktopControlBarState extends State<DesktopControlBar> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform(context)) return widget.child;
    return LayoutBuilder(builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final contentWidth = 700 * textScale.clamp(1.0, double.infinity);
      if (constraints.maxWidth >= contentWidth) return widget.child;
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus
          },
          scrollbars: false,
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: contentWidth, child: widget.child),
          ),
        ),
      );
    });
  }
}
