import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/danmaku_style.dart';

void main() {
  test('UI weight endpoints and malformed old weights remain in Flutter range',
      () {
    expect(DanmakuStyle.fontWeightIndex(1), 0);
    expect(DanmakuStyle.fontWeightIndex(4), 3);
    expect(DanmakuStyle.fontWeightIndex(9), 8);
    expect(DanmakuStyle.fontWeightIndex(-1), 0);
    expect(DanmakuStyle.fontWeightIndex(100), 8);
  });
  test('small window transforms settings without mutating normal style', () {
    const size = 30.0;
    const speed = 12.0;
    expect(DanmakuStyle.fontSize(size, smallWindow: true), 15);
    expect(DanmakuStyle.duration(speed, smallWindow: true), 6);
    expect(DanmakuStyle.fontSize(size, smallWindow: false), size);
    expect(DanmakuStyle.duration(speed, smallWindow: false), speed);
    expect(DanmakuStyle.fontSize(40, smallWindow: true), 20);
    expect(DanmakuStyle.fontSize(40, smallWindow: false), 40);
  });
  test('malformed style cannot propagate non-finite size or duration', () {
    expect(DanmakuStyle.clampSize(double.nan), 25);
    expect(DanmakuStyle.clampSize(-100), 8);
    expect(DanmakuStyle.clampSize(100), 72);
    expect(DanmakuStyle.duration(double.infinity, smallWindow: false), 10);
  });
}
