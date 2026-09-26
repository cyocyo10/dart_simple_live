import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Gives scrollable settings a bounded viewport without losing DPI or text scale.
class DesktopSettingsPanel extends StatelessWidget {
  const DesktopSettingsPanel({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.maxWidth = 600,
  });
  final String title;
  final Widget child;
  final VoidCallback onClose;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final available =
        media.size.height - media.viewInsets.vertical - media.padding.vertical;
    return SizedBox(
      width: math.max(0, math.min(maxWidth, media.size.width - 32)),
      height: math.max(0, math.min(560, available - 32)),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
