import '../simple_live_core/lib/src/douyu_stream_url.dart';
import '../simple_live_app/lib/modules/live_room/player/recovery_budget.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final cases = <List<String>>[
    [
      "https://cdn/live.flv?expire=300&fcdn=ws",
      "https://cdn/live.flv?expire=300&fcdn=ws&expire=0",
    ],
    [
      "https://cdn/live.flv?fcdn=ws&expire=300&token=a%2Fb+Z#part",
      "https://cdn/live.flv?fcdn=ws&expire=300&token=a%2Fb+Z&expire=0#part",
    ],
    [
      "https://cdn/live.flv?expire=300&fcdn=ws&",
      "https://cdn/live.flv?expire=300&fcdn=ws&expire=0",
    ],
    ["", ""],
    ["https://cdn/live.flv", "https://cdn/live.flv"],
    [
      "https://cdn/live.flv?expire=300&fcdn=hw",
      "https://cdn/live.flv?expire=300&fcdn=hw",
    ],
    [
      "https://cdn/live.flv?expire=3000&fcdn=ws",
      "https://cdn/live.flv?expire=3000&fcdn=ws",
    ],
    [
      "https://cdn/live.flv?expire=300&fcdn=ws2",
      "https://cdn/live.flv?expire=300&fcdn=ws2",
    ],
    [
      "https://cdn/live.flv?xexpire=300&fcdn=ws",
      "https://cdn/live.flv?xexpire=300&fcdn=ws",
    ],
    [
      "https://cdn/live.flv?expire=300&fcdn=ws&expire=0",
      "https://cdn/live.flv?expire=300&fcdn=ws&expire=0",
    ],
    [
      "https://cdn/live.flv?expire=300&fcdn=ws&fcdn=hw",
      "https://cdn/live.flv?expire=300&fcdn=ws&fcdn=hw",
    ],
    [
      "https://cdn/live.flv#expire=300&fcdn=ws",
      "https://cdn/live.flv#expire=300&fcdn=ws",
    ],
    [
      "https://cdn/live.flv?note=expire=300&fcdn=ws",
      "https://cdn/live.flv?note=expire=300&fcdn=ws",
    ],
  ];
  for (final item in cases) {
    final actual = normalizeDouyuStreamUrl(item[0]);
    check(actual == item[1], 'URL normalization mismatch');
    check(normalizeDouyuStreamUrl(actual) == actual, 'Not idempotent');
  }
  final budget = RecoveryBudget();
  for (var i = 0; i < 3; i++) {
    check(budget.tryAcquire(Duration(seconds: i)), 'Initial retry refused');
  }
  check(!budget.tryAcquire(const Duration(seconds: 3)), 'Burst not bounded');
  check(budget.tryAcquire(const Duration(seconds: 60)), 'Budget never renewed');
  for (var i = 1; i <= 20; i++) {
    check(
      budget.tryAcquire(Duration(minutes: 5 * i)),
      'Long live session exhausted',
    );
  }
  budget.reset();
  check(budget.count == 0, 'New selection did not reset budget');
  print(
    '${cases.length} URL cases, idempotence, bounded bursts and 20 renewals passed',
  );
}
