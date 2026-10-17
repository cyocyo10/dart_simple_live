/// Limit repeated failures without exhausting recovery for a long live session.
/// The caller supplies monotonic elapsed time, not the system wall clock.
class RecoveryBudget {
  final int maxAttempts;
  final Duration window;
  final List<Duration> _attempts = [];

  RecoveryBudget({
    this.maxAttempts = 3,
    this.window = const Duration(minutes: 1),
  });

  bool tryAcquire(Duration now) {
    _attempts.removeWhere((attempt) => now - attempt >= window);
    if (_attempts.length >= maxAttempts) return false;
    _attempts.add(now);
    return true;
  }

  int get count => _attempts.length;
  void reset() => _attempts.clear();
}
