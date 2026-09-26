import 'dart:async';
import 'dart:io';

import 'package:auto_orientation_v2/auto_orientation_v2.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:floating/floating.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/custom_throttle.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'danmaku_style.dart';
import 'package:simple_live_app/services/desktop_lifecycle_service.dart';

mixin PlayerMixin {
  GlobalKey<VideoState> globalPlayerKey = GlobalKey<VideoState>();
  GlobalKey globalDanmuKey = GlobalKey();

  /// 播放器实例
  late final player = Player(
    configuration: PlayerConfiguration(
      title: "Simple Live Player",
      // The central logger filters details dynamically in every window.
      logLevel: MPVLogLevel.info,
    ),
  );

  /// 初始化播放器并设置 ao 参数
  Future<void> initializePlayer() async {
    var pp = player.platform as NativePlayer;
    // 设置音频输出驱动
    if (AppSettingsController.instance.customPlayerOutput.value) {
      if (player.platform is NativePlayer) {
        await (player.platform as dynamic).setProperty(
          'ao',
          AppSettingsController.instance.audioOutputDriver.value,
        );
      }
    }
    // media_kit 仓库更新导致的问题，临时解决办法
    if (Platform.isAndroid) {
      await pp.setProperty('force-seekable', 'yes');
    }
  }

  /// 视频控制器
  late final videoController = VideoController(
    player,
    configuration: AppSettingsController.instance.customPlayerOutput.value
        ? VideoControllerConfiguration(
            vo: AppSettingsController.instance.videoOutputDriver.value,
            hwdec: AppSettingsController.instance.videoHardwareDecoder.value,
          )
        : AppSettingsController.instance.playerCompatMode.value
            ? const VideoControllerConfiguration(
                vo: 'mediacodec_embed',
                hwdec: 'mediacodec',
              )
            : VideoControllerConfiguration(
                enableHardwareAcceleration:
                    AppSettingsController.instance.hardwareDecode.value,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
  );
}

mixin PlayerStateMixin on PlayerMixin {
  ///音量控制条计时器
  Timer? hidevolumeTimer;

  /// 是否进入桌面端小窗
  RxBool smallWindowState = false.obs;

  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;

  /// Playback volume belongs to this window; the stored value is only a default.
  final playbackVolume = 100.0.obs;

  bool _desktopSilenced = false;
  bool _playerClosing = false;
  Future<void> _volumeCommands = Future<void>.value();
  Future<void>? _volumeDrain;
  bool _volumeDirty = false;

  Future<void> _applyRoomVolume() {
    _volumeDirty = true;
    if (_volumeDrain != null) return _volumeDrain!;
    final completion = Completer<void>();
    _volumeDrain = completion.future;
    // Dragging can produce updates faster than the native player responds.
    // Keep one call in flight and apply only the latest requested value next.
    _volumeCommands = completion.future.then<void>((_) {},
        onError: (Object error, StackTrace stack) {
      Log.e('设置播放器音量失败: $error', stack);
    });
    unawaited(_drainRoomVolume(completion));
    return completion.future;
  }

  Future<void> _drainRoomVolume(Completer<void> completion) async {
    try {
      var retriedLatest = false;
      while (_volumeDirty && !_playerClosing) {
        _volumeDirty = false;
        try {
          await player.setVolume(_desktopSilenced ? 0 : playbackVolume.value);
        } catch (_) {
          // A failed old value must not discard an update received in flight.
          // Retry the latest target once; a persistently broken player still exits.
          if (_volumeDirty && !_playerClosing && !retriedLatest) {
            retriedLatest = true;
            continue;
          }
          rethrow;
        }
      }
      completion.complete();
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      _volumeDrain = null;
    }
  }

  void setRoomVolume(double value, {bool persistDefault = true}) {
    if (_playerClosing) return;
    final volume = value.clamp(0.0, 100.0).toDouble();
    playbackVolume.value = volume;
    unawaited(_applyRoomVolume()); // The shared drain already handles errors.
    if (persistDefault) AppSettingsController.instance.setPlayerVolume(volume);
  }

  void adjustRoomVolume(double amount) {
    if (_playerClosing) return;
    setRoomVolume(playbackVolume.value + amount, persistDefault: false);
    _showRoomVolumeTip();
  }

  void _showRoomVolumeTip({bool autoHide = true}) {
    hidevolumeTimer?.cancel();
    gestureTipText.value = '音量 ${playbackVolume.value.round()}%';
    showGestureTip.value = true;
    if (autoHide) {
      hidevolumeTimer = Timer(const Duration(milliseconds: 900), () {
        showGestureTip.value = false;
      });
    }
  }

  Future<void> silenceForDesktopClose() {
    _desktopSilenced = true;
    return _applyRoomVolume();
  }

  Future<void> restoreAfterDesktopClose() {
    _desktopSilenced = false;
    return _applyRoomVolume();
  }

  /// 显示手势Tip
  RxBool showGestureTip = false.obs;

  /// 手势Tip文本
  RxString gestureTipText = "".obs;

  /// 显示提示底部Tip
  RxBool showBottomTip = false.obs;

  /// 提示底部Tip文本
  RxString bottomTipText = "".obs;

  /// 自动隐藏控制器计时器
  Timer? hideControlsTimer;

  /// 自动隐藏提示计时器
  Timer? hideSeekTipTimer;

  /// 是否为竖屏直播间
  var isVertical = false.obs;

  Widget? danmakuView;

  var showQualites = false.obs;
  var showLines = false.obs;

  /// 隐藏控制器
  void hideControls() {
    showControlsState.value = false;
    hideControlsTimer?.cancel();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    resetHideControlsTimer();
  }

  /// 开始隐藏控制器计时
  /// - 当点击控制器上时功能时需要重新计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();

    hideControlsTimer = Timer(const Duration(seconds: 5), hideControls);
  }

  void updateScaleMode() {
    var boxFit = BoxFit.contain;
    double? aspectRatio;
    if (player.state.width != null && player.state.height != null) {
      aspectRatio = player.state.width! / player.state.height!;
    }

    if (AppSettingsController.instance.scaleMode.value == 0) {
      boxFit = BoxFit.contain;
    } else if (AppSettingsController.instance.scaleMode.value == 1) {
      boxFit = BoxFit.fill;
    } else if (AppSettingsController.instance.scaleMode.value == 2) {
      boxFit = BoxFit.cover;
    } else if (AppSettingsController.instance.scaleMode.value == 3) {
      boxFit = BoxFit.contain;
      aspectRatio = 16 / 9;
    } else if (AppSettingsController.instance.scaleMode.value == 4) {
      boxFit = BoxFit.contain;
      aspectRatio = 4 / 3;
    }
    globalPlayerKey.currentState?.update(aspectRatio: aspectRatio, fit: boxFit);
  }
}

mixin PlayerDanmakuMixin on PlayerStateMixin {
  /// 弹幕控制器
  DanmakuController? danmakuController;

  final List<Worker> _danmakuWorkers = [];

  DanmakuOption get currentDanmakuOption {
    final settings = AppSettingsController.instance;
    return DanmakuOption(
      fontSize: DanmakuStyle.fontSize(
        settings.danmuSize.value,
        smallWindow: smallWindowState.value,
      ),
      fontWeight: DanmakuStyle.fontWeightIndex(settings.danmuFontWeight.value),
      fontFamily: settings.danmuFontFamily.value.isEmpty
          ? null
          : settings.danmuFontFamily.value,
      strokeWidth: settings.danmuStrokeWidth.value.clamp(0.0, 5.0).toDouble(),
      duration: DanmakuStyle.duration(
        settings.danmuSpeed.value,
        smallWindow: smallWindowState.value,
      ),
      area: settings.danmuArea.value.clamp(0.1, 1.0).toDouble(),
      opacity: settings.danmuOpacity.value.clamp(0.1, 1.0).toDouble(),
    );
  }

  void watchDanmakuSettings() {
    final settings = AppSettingsController.instance;
    _danmakuWorkers.add(
      everAll([
        settings.danmuSize,
        settings.danmuFontWeight,
        settings.danmuFontFamily,
        settings.danmuStrokeWidth,
        settings.danmuSpeed,
        settings.danmuArea,
        settings.danmuOpacity,
        smallWindowState,
      ], (_) => updateDanmuOption(currentDanmakuOption)),
    );
    _danmakuWorkers.add(
      ever(
        settings.danmuEnable,
        (bool enabled) => showDanmakuState.value = enabled,
      ),
    );
  }

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
    updateDanmuOption(currentDanmakuOption);
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }

  void disposeDanmakuController() {
    for (final worker in _danmakuWorkers) {
      worker.dispose();
    }
    _danmakuWorkers.clear();
    danmakuController?.clear();
    danmakuController = null;
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value) {
      return;
    }
    for (var item in items) {
      danmakuController?.addDanmaku(item);
    }
  }
}

mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  final pip = Floating();
  StreamSubscription<PiPStatus>? _pipSubscription;

  //final VolumeController volumeController = VolumeController();

  /// 初始化一些系统状态
  void initSystem() async {
    if (Platform.isAndroid || Platform.isIOS) {
      VolumeController.instance.showSystemUI = false;
    }

    // 屏幕常亮
    //WakelockPlus.enable();

    // 开始隐藏计时
    resetHideControlsTimer();

    // 进入全屏模式
    if (AppSettingsController.instance.autoFullScreen.value) {
      enterFullScreen();
    }
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    _pipSubscription?.cancel();
    //pip.dispose();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    await setPortraitOrientation();
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // 亮度重置,桌面平台可能会报错,暂时不处理桌面平台的亮度
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      } catch (e) {
        Log.logPrint(e);
      }
    }

    await WakelockPlus.disable();
  }

  bool desktopFullScreenState = false;
  bool _windowTransitioning = false;
  Size? _lastWindowSize;
  Offset? _lastWindowPosition;
  bool _lastAlwaysOnTop = false;

  /// All desktop mode changes are serialized within this playback window.
  Future<void> enterFullScreen() async {
    if (_windowTransitioning) return;
    if (Platform.isAndroid || Platform.isIOS) {
      fullScreenState.value = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      if (!isVertical.value) setLandscapeOrientation();
      return;
    }
    _windowTransitioning = true;
    try {
      if (smallWindowState.value) await _restoreSmallWindow();
      await windowManager.setFullScreen(true);
      desktopFullScreenState = true;
      fullScreenState.value = true;
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> exitFull() async {
    if (_windowTransitioning) return;
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values);
      setPortraitOrientation();
      fullScreenState.value = false;
      return;
    }
    _windowTransitioning = true;
    try {
      if (smallWindowState.value) await _restoreSmallWindow();
      if (desktopFullScreenState) await windowManager.setFullScreen(false);
      desktopFullScreenState = false;
      fullScreenState.value = false;
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> enterWindowFullScreen() async {
    if (_windowTransitioning) return;
    _windowTransitioning = true;
    try {
      if (smallWindowState.value) await _restoreSmallWindow();
      if (desktopFullScreenState) await windowManager.setFullScreen(false);
      desktopFullScreenState = false;
      fullScreenState.value = true;
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> enterSmallWindow() async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        _windowTransitioning ||
        smallWindowState.value) return;
    _windowTransitioning = true;
    try {
      if (desktopFullScreenState) await windowManager.setFullScreen(false);
      desktopFullScreenState = false;
      _lastWindowSize = await windowManager.getSize();
      _lastWindowPosition = await windowManager.getPosition();
      _lastAlwaysOnTop = await windowManager.isAlwaysOnTop();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      final width = player.state.width ?? 16;
      final height = player.state.height ?? 9;
      final ratio = width > 0 && height > 0 ? width / height : 16 / 9;
      await windowManager
          .setSize(ratio < 1 ? Size(400, 400 / ratio) : Size(280 * ratio, 280));
      await windowManager.setAlwaysOnTop(true);
      fullScreenState.value = true;
      smallWindowState.value = true;
    } finally {
      _windowTransitioning = false;
    }
  }

  Future<void> _restoreSmallWindow() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    if (_lastWindowSize != null) await windowManager.setSize(_lastWindowSize!);
    if (_lastWindowPosition != null)
      await windowManager.setPosition(_lastWindowPosition!);
    await windowManager.setAlwaysOnTop(_lastAlwaysOnTop);
    smallWindowState.value = false;
    fullScreenState.value = false;
  }

  Future<void> exitSmallWindow() async {
    if (!smallWindowState.value || _windowTransitioning) return;
    _windowTransitioning = true;
    try {
      await _restoreSmallWindow();
    } finally {
      _windowTransitioning = false;
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    if (await beforeIOS16()) {
      AutoOrientation.landscapeAutoMode();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    if (await beforeIOS16()) {
      AutoOrientation.portraitAutoMode();
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  /// 是否是IOS16以下
  Future<bool> beforeIOS16() async {
    if (Platform.isIOS) {
      var info = await deviceInfo.iosInfo;
      var version = info.systemVersion;
      var versionInt = int.tryParse(version.split('.').first) ?? 0;
      return versionInt < 16;
    } else {
      return false;
    }
  }

  Future saveScreenshot() async {
    try {
      SmartDialog.showLoading(msg: "正在保存截图");
      //检查相册权限,仅iOS需要
      var permission = await Utils.checkPhotoPermission();
      if (!permission) {
        SmartDialog.showToast("没有相册权限");
        SmartDialog.dismiss(status: SmartStatus.loading);
        return;
      }

      var imageData = await player.screenshot();
      if (imageData == null) {
        SmartDialog.showToast("截图失败,数据为空");
        SmartDialog.dismiss(status: SmartStatus.loading);
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        await ImageGallerySaverPlus.saveImage(imageData);
        SmartDialog.showToast("已保存截图至相册");
      } else {
        //选择保存文件夹
        var path = await FilePicker.platform.saveFile(
          allowedExtensions: ["jpg"],
          type: FileType.image,
          fileName: "${DateTime.now().millisecondsSinceEpoch}.jpg",
        );
        if (path == null) {
          SmartDialog.showToast("取消保存");
          SmartDialog.dismiss(status: SmartStatus.loading);
          return;
        }
        var file = File(path);
        await file.writeAsBytes(imageData);
        SmartDialog.showToast("已保存截图至${file.path}");
      }
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("截图失败");
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  /// 开启小窗播放前弹幕状态
  bool danmakuStateBeforePIP = false;

  Future enablePIP() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (await pip.isPipAvailable == false) {
      SmartDialog.showToast("设备不支持小窗播放");
      return;
    }
    danmakuStateBeforePIP = showDanmakuState.value;
    //关闭并清除弹幕
    if (AppSettingsController.instance.pipHideDanmu.value &&
        danmakuStateBeforePIP) {
      showDanmakuState.value = false;
    }
    danmakuController?.clear();
    //关闭控制器
    showControlsState.value = false;

    //监听事件
    var width = player.state.width ?? 0;
    var height = player.state.height ?? 0;
    Rational ratio = const Rational.landscape();
    if (height > width) {
      ratio = const Rational.vertical();
    } else {
      ratio = const Rational.landscape();
    }
    await pip.enable(ImmediatePiP(aspectRatio: ratio));

    _pipSubscription ??= pip.pipStatusStream.listen((event) {
      if (event == PiPStatus.disabled) {
        danmakuController?.clear();
        showDanmakuState.value = danmakuStateBeforePIP;
      }
      Log.w(event.toString());
    });
  }
}

mixin PlayerGestureControlMixin
    on PlayerStateMixin, PlayerMixin, PlayerSystemMixin {
  /// 单击显示/隐藏控制器
  void onTap() {
    if (showControlsState.value) {
      hideControls();
    } else {
      showControls();
    }
  }

  //桌面端操控
  void onEnter(PointerEnterEvent event) {
    if (!showControlsState.value) {
      showControls();
    }
  }

  void onExit(PointerExitEvent event) {
    if (showControlsState.value) {
      hideControls();
    }
  }

  void onHover(PointerHoverEvent event, BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final targetPosition = screenHeight * 0.25; // 计算屏幕顶部25%的位置
    if (event.position.dy <= targetPosition ||
        event.position.dy >= targetPosition * 3) {
      if (!showControlsState.value) {
        showControls();
      }
    }
  }

  /// 双击全屏/退出全屏
  void onDoubleTap(TapDownDetails details) {
    if (lockControlsState.value) {
      return;
    }
    if (fullScreenState.value) {
      exitFull();
    } else {
      enterFullScreen();
    }
  }

  bool verticalDragging = false;
  bool leftVerticalDrag = false;
  bool _desktopVolumeDragging = false;
  double _desktopVolumeDragHeight = 1;
  var _currentVolume = 0.0;
  var _currentBrightness = 1.0;
  var verStartPosition = 0.0;

  DelayedThrottle? throttle;

  /// 竖向手势开始
  void onVerticalDragStart(DragStartDetails details,
      {double? viewportHeight}) async {
    if (_playerClosing || (lockControlsState.value && fullScreenState.value)) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      if (details.kind != PointerDeviceKind.mouse ||
          viewportHeight == null ||
          !viewportHeight.isFinite ||
          viewportHeight <= 0) {
        return;
      }
      // Match AllLive's sensitivity: 80% of the video height spans 0–100%.
      // Desktop controls affect this player, never the OS-wide volume.
      _desktopVolumeDragHeight = viewportHeight;
      _desktopVolumeDragging = true;
      verticalDragging = true;
      _showRoomVolumeTip(autoHide: false);
      return;
    }

    final dy = details.globalPosition.dy;
    // 开始位置必须是中间2/4的位置
    if (dy < Get.height * 0.25 || dy > Get.height * 0.75) {
      return;
    }

    verStartPosition = dy;
    leftVerticalDrag = details.globalPosition.dx < Get.width / 2;

    throttle = DelayedThrottle(200);

    verticalDragging = true;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      showGestureTip.value = true;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _currentVolume = await VolumeController.instance.getVolume();
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _currentBrightness = await ScreenBrightness.instance.application;
    }
  }

  /// 竖向手势更新
  void onVerticalDragUpdate(DragUpdateDetails e) async {
    if (_playerClosing || (lockControlsState.value && fullScreenState.value)) {
      onVerticalDragCancel();
      return;
    }
    if (verticalDragging == false) return;
    if (_desktopVolumeDragging) {
      setRoomVolume(
        playbackVolume.value -
            e.delta.dy * 100 / (_desktopVolumeDragHeight * 0.8),
        persistDefault: false,
      );
      _showRoomVolumeTip(autoHide: false);
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    //String text = "";
    //double value = 0.0;

    if (leftVerticalDrag) {
      setGestureBrightness(e.globalPosition.dy);
    } else {
      setGestureVolume(e.globalPosition.dy);
    }
  }

  int lastVolume = -1; // it's ok to be -1

  void setGestureVolume(double dy) {
    double value = 0.0;
    double seek;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      seek = _currentVolume - value;
      if (seek < 0) {
        seek = 0;
      }
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      seek = value.abs() + _currentVolume;
      if (seek > 1) {
        seek = 1;
      }
    }
    int volume = _convertVolume((seek * 100).round());
    if (volume == lastVolume) {
      return;
    }
    lastVolume = volume;
    // update UI outside throttle to make it more fluent
    gestureTipText.value = "音量 $volume%";
    throttle?.invoke(() async => await _realSetVolume(volume));
  }

  // 0 to 100, 5 step each
  int _convertVolume(int volume) {
    return (volume / 5).round() * 5;
  }

  Future _realSetVolume(int volume) async {
    VolumeController.instance.setVolume(volume / 100);
  }

  void setGestureBrightness(double dy) {
    double value = 0.0;
    if (dy > verStartPosition) {
      value = ((dy - verStartPosition) / (Get.height * 0.5));

      var seek = _currentBrightness - value;
      if (seek < 0) {
        seek = 0;
      }
      ScreenBrightness.instance.setApplicationScreenBrightness(seek);

      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
    } else {
      value = ((dy - verStartPosition) / (Get.height * 0.5));
      var seek = value.abs() + _currentBrightness;
      if (seek > 1) {
        seek = 1;
      }

      ScreenBrightness.instance.setApplicationScreenBrightness(seek);
      gestureTipText.value = "亮度 ${(seek * 100).toInt()}%";
    }
  }

  /// 竖向手势完成
  void onVerticalDragEnd(DragEndDetails details) => onVerticalDragCancel();

  /// A cancelled pointer must not leave the volume gesture or its OSD active.
  void onVerticalDragCancel() {
    _desktopVolumeDragging = false;
    throttle = null;
    verticalDragging = false;
    leftVerticalDrag = false;
    showGestureTip.value = false;
  }
}

class PlayerController extends BaseController
    with
        PlayerMixin,
        PlayerStateMixin,
        PlayerDanmakuMixin,
        PlayerSystemMixin,
        PlayerGestureControlMixin {
  @override
  void onInit() {
    watchDanmakuSettings();
    initSystem();
    initStream();
    //设置音量
    setRoomVolume(AppSettingsController.instance.playerVolume.value,
        persistDefault: false);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      DesktopLifecycleService.instance.register(
          this,
          DesktopCloseParticipant(
            silence: silenceForDesktopClose,
            restore: restoreAfterDesktopClose,
            finish: disposePlayer,
          ));
    }
    super.onInit();
  }

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;
  StreamSubscription? _logSubscription;
  StreamSubscription? _playingSubscription;

  void initStream() {
    _errorSubscription = player.stream.error.listen((event) {
      Log.e("播放器错误：$event", StackTrace.current);
      // 跳过无音频输出的错误
      // Could not open/initialize audio device -> no sound.
      if (event.contains('no sound.')) {
        return;
      }
      //SmartDialog.showToast(event);
      mediaError(event);
    });

    _playingSubscription = player.stream.playing.listen((event) {
      if (event) {
        WakelockPlus.enable();
        Log.d("Playing");
      }
    });

    _completedSubscription = player.stream.completed.listen((event) {
      if (event) {
        mediaEnd();
      }
    });
    _logSubscription = player.stream.log.listen((event) {
      if (event.level == 'error' || event.level == 'fatal') {
        Log.e('播放器日志：$event', StackTrace.current);
      } else if (event.level == 'warn') {
        Log.w('播放器日志：$event');
      } else {
        Log.d('播放器日志：$event');
      }
    });
    _widthSubscription = player.stream.width.listen((event) {
      Log.d(
        'width:$event  W:${(player.state.width)}  H:${(player.state.height)}',
      );
      isVertical.value =
          (player.state.height ?? 9) > (player.state.width ?? 16);
    });
    _heightSubscription = player.stream.height.listen((event) {
      Log.d(
        'height:$event  W:${(player.state.width)}  H:${(player.state.height)}',
      );
      isVertical.value =
          (player.state.height ?? 9) > (player.state.width ?? 16);
    });
  }

  void disposeStream() {
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    _logSubscription?.cancel();
    _pipSubscription?.cancel();
    _playingSubscription?.cancel();
  }

  void mediaEnd() {
    WakelockPlus.disable();
  }

  void mediaError(String error) {
    WakelockPlus.disable();
  }

  void showDebugInfo() {
    Utils.showBottomSheet(
      title: "播放信息",
      child: ListView(
        children: [
          ListTile(
            title: const Text("Resolution"),
            subtitle: Text('${player.state.width}x${player.state.height}'),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text:
                      "Resolution\n${player.state.width}x${player.state.height}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("VideoParams"),
            subtitle: Text(player.state.videoParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "VideoParams\n${player.state.videoParams}"),
              );
            },
          ),
          ListTile(
            title: const Text("AudioParams"),
            subtitle: Text(player.state.audioParams.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "AudioParams\n${player.state.audioParams}"),
              );
            },
          ),
          ListTile(
            title: const Text("Media"),
            subtitle: Text(player.state.playlist.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "Media\n${player.state.playlist}"),
              );
            },
          ),
          ListTile(
            title: const Text("AudioTrack"),
            subtitle: Text(player.state.track.audio.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "AudioTrack\n${player.state.track.audio}"),
              );
            },
          ),
          ListTile(
            title: const Text("VideoTrack"),
            subtitle: Text(player.state.track.video.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "VideoTrack\n${player.state.track.audio}"),
              );
            },
          ),
          ListTile(
            title: const Text("AudioBitrate"),
            subtitle: Text(player.state.audioBitrate.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(
                  text: "AudioBitrate\n${player.state.audioBitrate}",
                ),
              );
            },
          ),
          ListTile(
            title: const Text("Volume"),
            subtitle: Text(player.state.volume.toString()),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: "Volume\n${player.state.volume}"),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> beforePlayerDispose() async {}
  void preparePlayerClose() {}
  Future<void>? _playerDisposal;

  Future<void> disposePlayer() => _playerDisposal ??= _disposePlayer();

  Future<void> _disposePlayer() async {
    _playerClosing = true;
    preparePlayerClose();
    hideControlsTimer?.cancel();
    hidevolumeTimer?.cancel();
    hideSeekTipTimer?.cancel();
    disposeStream();
    disposeDanmakuController();
    await beforePlayerDispose();
    await _volumeCommands;
    Log.w("播放器关闭");
    if (smallWindowState.value) {
      await exitSmallWindow();
    }
    await resetSystem();
    await player.dispose();
  }

  @override
  void onClose() {
    DesktopLifecycleService.instance.unregister(this);
    unawaited(disposePlayer().catchError((Object error, StackTrace stack) {
      Log.e('播放器清理失败: $error', stack);
    }));
    super.onClose();
  }
}
