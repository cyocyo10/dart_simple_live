import '../../lib/modules/mine/history/history_transfer.dart';
import '../../lib/modules/mine/account/douyu/login_cookie.dart';

void require(bool result, String message) {
  if (!result) throw StateError(message);
}

void main() {
  const old = '{"siteId":"douyu","id":"douyu_1","roomId":"1",'
      '"userName":"主播","face":"","updateTime":"2025-01-02 03:04:05"}';
  const newer = '{"siteId":"douyu","id":"douyu_1","roomId":"1",'
      '"userName":"新主播","face":"","updateTime":"2026-01-02 03:04:05"}';
  final rows = HistoryTransfer.decode('[$newer,$old]');
  require(
    rows.length == 1 && rows.values.single['userName'] == '新主播',
    'Duplicate rooms must keep latest timestamp',
  );
  require(
    HistoryTransfer.decode(HistoryTransfer.encode(rows.values)).length == 1,
    'Export must round trip',
  );
  require(
    HistoryTransfer.decode('[]').isEmpty,
    'Empty imports remain harmless',
  );
  for (final source in [
    '{}',
    '[$old,{}]',
    old.replaceFirst('douyu_1', 'wrong'),
  ]) {
    try {
      HistoryTransfer.decode(source);
      throw StateError('Malformed import accepted');
    } on FormatException {
      // Whole-file validation must reject without producing partial data.
    }
  }
  require(
    isDouyuHost('www.douyu.com') && isDouyuHost('douyu.com'),
    'Douyu host',
  );
  require(
    !isDouyuHost('evil-douyu.com') && !isDouyuHost('douyu.com.evil'),
    'Domain boundary must reject lookalikes',
  );
  require(hasDouyuSession('acf_uid=123; acf_auth=token'), 'Logged in cookie');
  require(
    !hasDouyuSession('acf_uid=0; acf_auth=token') &&
        !hasDouyuSession('acf_did=device'),
    'Anonymous cookie must not mark login',
  );
  print(
    'PASS: AllLive JSON round trip, duplicate merge, invalid/empty input, '
    'Douyu domain boundary and session detection',
  );
}
