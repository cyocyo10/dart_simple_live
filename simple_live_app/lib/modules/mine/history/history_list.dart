import 'package:flutter/material.dart';
import 'package:simple_live_app/models/db/history.dart';

/// Row-based columns preserve reading order even when card heights differ.
class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.controller,
    this.wrapList,
  });

  final List<History> items;
  final Widget Function(BuildContext context, History item) itemBuilder;
  final ScrollController? controller;
  final Widget Function(Widget list)? wrapList;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final breakpoint = 840 * (scale < 1 ? 1 : scale);
      final columns = constraints.maxWidth >= breakpoint ? 2 : 1;
      final rowCount = (items.length / columns).ceil();
      final list = ListView.separated(
        controller: controller,
        padding: const EdgeInsets.all(12),
        itemCount: rowCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final first = index * columns;
          final end = first + columns < items.length
              ? first + columns
              : items.length;
          final row = items.sublist(first, end);
          return Row(
            key: ValueKey('history-row-${row.map((e) => e.id).join('|')}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 12),
                Expanded(
                  child: column < row.length
                      ? itemBuilder(context, row[column])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
        },
      );
      return wrapList?.call(list) ?? list;
    },
  );
}
