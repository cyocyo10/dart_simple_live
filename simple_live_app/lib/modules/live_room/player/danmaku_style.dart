/// Values are logical pixels, independent of Windows display DPI.
class DanmakuStyle {
  static double clampSize(double value) =>
      value.isFinite ? value.clamp(8.0, 72.0).toDouble() : 25.0;

  /// Settings use weights 1..9; Flutter/canvas_danmaku use indices 0..8.
  static int fontWeightIndex(int value) => value.clamp(1, 9) - 1;

  static double fontSize(double value, {required bool smallWindow}) =>
      clampSize(value) * (smallWindow ? 0.5 : 1.0);

  static double duration(double value, {required bool smallWindow}) =>
      smallWindow
          ? 6.0
          : (value.isFinite ? value.clamp(4.0, 20.0).toDouble() : 10.0);
}
