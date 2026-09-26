import 'package:flutter/material.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// A chronological history entry that remains readable in narrow windows.
class HistoryRow extends StatelessWidget {
  const HistoryRow({
    super.key,
    required this.item,
    required this.site,
    required this.status,
    this.onTap,
    this.onLongPress,
  });

  final History item;
  final Site? site;
  final int status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusText = switch (status) {
      1 => '未开播',
      2 => '直播中',
      3 => '回放中',
      _ => '状态未知',
    };
    final statusColor = switch (status) {
      2 => colors.primary,
      3 => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    final name = item.userName.trim();
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetImage(
                item.face,
                key: ValueKey('history-avatar-${item.id}'),
                width: 48,
                height: 48,
                borderRadius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '房间 ${item.roomId}' : name,
                      key: ValueKey('history-name-${item.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          site?.name ?? '暂不支持的平台',
                          key: ValueKey('history-platform-${item.id}'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            key: ValueKey('history-status-${item.id}'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '观看于 ${Utils.parseTime(item.updateTime.toLocal())}',
                      key: ValueKey('history-time-${item.id}'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
