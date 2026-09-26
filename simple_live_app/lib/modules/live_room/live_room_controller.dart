import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/live_room/player/playback_lifecycle.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/desktop_lifecycle_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  // One timestamp per user visit; retries and refreshes only update metadata.
  DateTime _openedAt;

  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
    DateTime? openedAt,
  }) : _openedAt = openedAt ?? DateTime.now() {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;
  Timer? _autoExitGraceTimer;
  int _autoExitGeneration = 0;
  bool _autoExiting = false;
  final PlaybackLifecycle _playback = PlaybackLifecycle();
  bool _playerHasCurrentPlaylist = false;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Error? error;

  // 开播时长状态变量
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;
  StreamSubscription<dynamic>? _followSubscription;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _followSubscription = EventBus.instance.listen(Constant.kUpdateFollow, (_) {
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    });
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    // 延迟到下一帧，确保 SmartDialog overlay 在子窗口中已就绪
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadData();
    });

    scrollController.addListener(scrollListener);

    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit({bool resetCountdown = true}) {
    final generation = ++_autoExitGeneration;
    autoExitTimer?.cancel();
    _autoExitGraceTimer?.cancel();
    if (!autoExitEnable.value || !_playback.ownsRoom(_playback.current.room)) {
      return;
    }
    if (resetCountdown) countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (generation != _autoExitGeneration) return;
      countdown.value -= 1;
      if (countdown.value > 0) return;
      timer.cancel();
      _autoExitGraceTimer = Timer(const Duration(seconds: 10), () {
        if (generation == _autoExitGeneration) shutdownAfterCountdown();
      });
      final delay = await askAutoExitDelay();
      if (generation != _autoExitGeneration ||
          !_playback.ownsRoom(_playback.current.room)) {
        return;
      }
      _autoExitGraceTimer?.cancel();
      if (delay) {
        delayAutoExit.value = true;
        showAutoExitSheet();
        setAutoExit();
      } else {
        delayAutoExit.value = false;
        await shutdownAfterCountdown();
      }
    });
  }

  Future<bool> askAutoExitDelay() => Utils.showAlertDialog(
        "定时关闭已到时,是否延迟关闭?",
        title: "延迟关闭",
        confirm: "延迟",
        cancel: "关闭",
        selectable: true,
      );

  Future<void> shutdownAfterCountdown() async {
    if (_autoExiting || !_playback.ownsRoom(_playback.current.room)) return;
    _autoExiting = true;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Desktop saving can fail: leave the room recoverable until teardown.
      await DesktopLifecycleService.instance.closeProcess();
      _autoExiting = false;
    } else {
      _playback.close();
      autoExitTimer?.cancel();
      _autoExitGraceTimer?.cancel();
      await _playback.drained;
      await WakelockPlus.disable();
      await DBService.instance.historyBox.flush();
      await LocalStorageService.instance.settingsBox.flush();
      await LocalStorageService.instance.shieldBox.flush();
      await Log.shutdown();
      exit(0);
    }
  }
  // 弹窗逻辑

  void refreshRoom() {
    //messages.clear();
    superChats.clear();
    liveDanmaku.stop();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      if (messages.length > 200 && !disableAutoScroll.value) {
        messages.removeAt(0);
      }

      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      messages.add(msg);

      WidgetsBinding.instance.addPostFrameCallback((_) => chatScrollToBottom());
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      superChats.add(msg.data);
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  void showRoomLoading() => SmartDialog.showLoading(msg: "");
  void hideRoomLoading() => SmartDialog.dismiss(status: SmartStatus.loading);
  void showRoomToast(String message) => SmartDialog.showToast(message);

  _RoomRequest _captureRoom(int generation) =>
      _RoomRequest(generation, site, roomId, liveDanmaku);

  /// Each asynchronous result belongs to the room that requested it.
  Future<void> loadData() async {
    final room = _captureRoom(_playback.beginRoom());
    if (!_playback.ownsRoom(room.generation)) return;
    try {
      showRoomLoading();
      loadError.value = false;
      error = null;
      _playerHasCurrentPlaylist = false;
      detail.value = null;
      liveStatus.value = false;
      qualites.clear();
      playUrls.clear();
      currentQuality = currentLineIndex = -1;
      update();
      addSysMsg("正在读取直播间信息");
      final result = await room.site.liveSite.getRoomDetail(
        roomId: room.roomId,
      );
      if (!_playback.ownsRoom(room.generation)) return;
      detail.value = result;

      if (room.site.id == Constant.kDouyin && result.roomId != room.roomId) {
        final oldId = room.roomId;
        room.roomId = result.roomId;
        rxRoomId.value = result.roomId;
        if (followed.value) {
          try {
            // Keep the favorite and its tags together when resolving an alias.
            await DBService.instance.canonicalizeFollow(
              "${room.site.id}_$oldId",
              FollowUser(
                id: "${room.site.id}_${room.roomId}",
                roomId: room.roomId,
                siteId: room.site.id,
                userName: result.userName,
                face: result.userAvatar,
                addTime: DateTime.now(),
              ),
            );
            if (!_playback.ownsRoom(room.generation)) return;
            EventBus.instance.emit(
              Constant.kUpdateFollow,
              "${room.site.id}_${room.roomId}",
            );
          } catch (e) {
            Log.logPrint(e);
          }
        }
      }
      if (!_playback.ownsRoom(room.generation)) return;
      getSuperChatMessage();
      await addHistory();
      if (!_playback.ownsRoom(room.generation)) return;
      followed.value = DBService.instance.getFollowExist(
        "${room.site.id}_${room.roomId}",
      );
      online.value = result.online;
      liveStatus.value = result.status || result.isRecord;
      if (liveStatus.value) getPlayQualites();
      if (result.isRecord) addSysMsg("当前主播未开播，正在轮播录像");
      addSysMsg("开始连接弹幕服务器");
      // Old adapters can still deliver queued callbacks after stop.
      room.danmaku.onMessage = (message) {
        if (_playback.ownsRoom(room.generation)) onWSMessage(message);
      };
      room.danmaku.onClose = (message) {
        if (_playback.ownsRoom(room.generation)) onWSClose(message);
      };
      room.danmaku.onReady = () {
        if (_playback.ownsRoom(room.generation)) onWSReady();
      };
      await room.danmaku.start(result.danmakuData);
      if (!_playback.ownsRoom(room.generation)) return;
      startLiveDurationTimer();
    } catch (e, st) {
      if (!_playback.ownsRoom(room.generation)) return;
      Log.e(e.toString(), st);
      loadError.value = true;
      error = e is Error ? e : StateError(e.toString());
    } finally {
      if (_playback.ownsRoom(room.generation)) hideRoomLoading();
    }
  }

  Future<void> getPlayQualites() async {
    final request = _playback.beginPlayback();
    final requestSite = site;
    final requestDetail = detail.value;
    if (!_playback.owns(request) || requestDetail == null) return;
    qualites.clear();
    currentQuality = -1;
    try {
      final result = await requestSite.liveSite.getPlayQualites(
        detail: requestDetail,
      );
      if (!_playback.owns(request)) return;
      if (result.isEmpty) {
        showRoomToast("无法读取播放清晰度");
        return;
      }
      qualites.value = result;
      final level = await getQualityLevel();
      if (!_playback.owns(request)) return;
      currentQuality = level == 2
          ? 0
          : level == 0
              ? result.length - 1
              : result.length ~/ 2;
      await _resolvePlayUrls(
        request,
        requestSite,
        requestDetail,
        result[currentQuality],
      );
    } catch (e, st) {
      if (!_playback.owns(request)) return;
      Log.e("无法读取播放清晰度: $e", st);
      showRoomToast("无法读取播放清晰度");
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.mobile)) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  Future<void> getPlayUrl() async {
    final request = _playback.beginPlayback();
    final requestDetail = detail.value;
    if (!_playback.owns(request) ||
        requestDetail == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }
    await _resolvePlayUrls(
      request,
      site,
      requestDetail,
      qualites[currentQuality],
    );
  }

  Future<void> _resolvePlayUrls(
    PlaybackRequest request,
    Site requestSite,
    LiveRoomDetail requestDetail,
    LivePlayQuality quality,
  ) async {
    if (!_playback.owns(request)) return;
    _playerHasCurrentPlaylist = false;
    playUrls.clear();
    currentQualityInfo.value = quality.quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    playUrlResolveCount = 0;
    try {
      final result = await requestSite.liveSite.getPlayUrls(
        detail: requestDetail,
        quality: quality,
      );
      if (!_playback.owns(request)) return;
      if (result.urls.isEmpty) {
        showRoomToast("无法读取播放地址");
        return;
      }
      _playerHasCurrentPlaylist = false;
      playUrls.value = result.urls;
      playHeaders = result.headers;
      currentLineIndex = 0;
      mediaErrorRetryCount = 0;
      await _initPlaylist(request);
    } catch (e, st) {
      if (!_playback.owns(request)) return;
      Log.e("无法读取播放地址: $e", st);
      showRoomToast("无法读取播放地址");
    }
  }

  void changePlayLine(int index) {
    if (index < 0 || index >= playUrls.length) return;
    currentLineIndex = index;
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  Future<void> initPlaylist() => _initPlaylist(_playback.beginPlayback());

  Future<void> _initPlaylist(PlaybackRequest request) async {
    if (!_playback.owns(request) || playUrls.isEmpty) return;
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";
    final headers =
        playHeaders == null ? null : Map<String, String>.from(playHeaders!);
    final forceHttps = AppSettingsController.instance.playerForceHttps.value;
    final list = playUrls
        .map(
          (url) => Media(
            forceHttps ? url.replaceAll("http://", "https://") : url,
            httpHeaders: headers,
          ),
        )
        .toList();
    final line = currentLineIndex.clamp(0, list.length - 1);
    final opened = await _playback.open(
      request,
      initialize: initializePlayer,
      open: () => player.open(Playlist(list, index: line)),
    );
    if (opened) _playerHasCurrentPlaylist = true;
  }

  Future<void> setPlayer() async {
    final request = _playback.beginPlayback();
    final line = currentLineIndex;
    if (!_playback.owns(request) || line < 0 || line >= playUrls.length) return;
    currentLineInfo.value = "线路${line + 1}";
    errorMsg.value = "";
    try {
      if (!_playerHasCurrentPlaylist) {
        await _initPlaylist(request);
      } else {
        await _playback.command(request, () => player.jump(line));
      }
    } catch (e, st) {
      if (_playback.owns(request)) Log.e("切换线路失败: $e", st);
    }
  }

  @override
  void mediaEnd() {
    if (!_playback.owns(_playback.current)) return;
    super.mediaEnd();
    _handleMediaFailure();
  }

  int mediaErrorRetryCount = 0;

  /// 断流后重新取流(重新签名)的次数上限，防止无限重试
  int playUrlResolveCount = 0;
  static const int _maxPlayUrlResolveCount = 3;

  /// 所有线路均失败后，重新调用取流接口获取新签名地址。
  /// 斗鱼 H5 流带 5 分钟 wsAuth 短签名，断线后旧 URL 重试/换线都是无效的，
  /// 必须重新签名取流。返回 true 表示已用新地址继续播放。
  Future<bool> _reResolvePlayUrls() async {
    final request = _playback.current;
    final requestSite = site;
    final requestDetail = detail.value;
    if (!_playback.owns(request) ||
        requestDetail == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length ||
        playUrlResolveCount >= _maxPlayUrlResolveCount) {
      return false;
    }
    final quality = qualites[currentQuality];
    playUrlResolveCount += 1;
    Log.d("所有线路失败，重新获取播放地址(第$playUrlResolveCount次)");
    try {
      final result = await requestSite.liveSite.getPlayUrls(
        detail: requestDetail,
        quality: quality,
      );
      if (!_playback.owns(request) || result.urls.isEmpty) return false;
      _playerHasCurrentPlaylist = false;
      playUrls.value = result.urls;
      playHeaders = result.headers;
      currentLineIndex = 0;
      mediaErrorRetryCount = 0;
      await _initPlaylist(request);
      return _playback.owns(request);
    } catch (e, st) {
      if (_playback.owns(request)) Log.e("重取播放地址失败: $e", st);
      return false;
    }
  }

  PlaybackRequest? _handlingMediaFailure;

  @override
  void mediaError(String error) {
    if (!_playback.owns(_playback.current)) return;
    super.mediaError(error);
    _handleMediaFailure(error: error);
  }

  Future<void> _handleMediaFailure({String? error}) async {
    final request = _playback.current;
    if (!_playback.owns(request) ||
        playUrls.isEmpty ||
        (_handlingMediaFailure != null &&
            _playback.owns(_handlingMediaFailure!))) {
      return;
    }
    _handlingMediaFailure = request;
    try {
      if (mediaErrorRetryCount < 2) {
        if (mediaErrorRetryCount == 1) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!_playback.owns(request)) return;
        mediaErrorRetryCount++;
        await setPlayer();
        return;
      }
      if (playUrls.length - 1 != currentLineIndex) {
        changePlayLine(currentLineIndex + 1);
        return;
      }
      final resolved = await _reResolvePlayUrls();
      if (!_playback.owns(request)) return;
      if (!resolved) {
        if (error == null) {
          liveStatus.value = false;
        } else {
          errorMsg.value = "播放失败";
          showRoomToast("播放失败:$error");
        }
      }
    } catch (e, st) {
      if (_playback.owns(request)) Log.e("播放器重试失败: $e", st);
    } finally {
      if (identical(_handlingMediaFailure, request)) {
        _handlingMediaFailure = null;
      }
    }
  }

  /// 读取SC
  void getSuperChatMessage() async {
    final room = _captureRoom(_playback.current.room);
    final requestDetail = detail.value;
    if (!_playback.ownsRoom(room.generation) || requestDetail == null) return;
    try {
      final messages = await room.site.liveSite.getSuperChatMessage(
        roomId: requestDetail.roomId,
      );
      if (_playback.ownsRoom(room.generation)) superChats.addAll(messages);
    } catch (e) {
      if (!_playback.ownsRoom(room.generation)) return;
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
  }

  /// 添加历史记录（必须 await + flush，否则 Windows 上重启后丢失）
  Future<void> addHistory() async {
    if (detail.value == null) {
      return;
    }
    try {
      var id = "${site.id}_$roomId";
      final existing = DBService.instance.getHistory(id);
      // Do not mutate a cached Hive/shared-store object: that would destroy
      // the timestamp needed by the storage guard to reject a stale window.
      final room = detail.value!;
      final history = History(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: room.userName.trim().isEmpty
            ? existing?.userName ?? ''
            : room.userName,
        face: room.userAvatar.isEmpty ? existing?.face ?? '' : room.userAvatar,
        updateTime: _openedAt,
      );

      await DBService.instance.addOrUpdateHistory(history);
      EventBus.instance.emit(Constant.kUpdateHistory, id);
      Log.d("History saved: $id");
    } catch (e, st) {
      Log.logPrint(e);
      Log.e("保存观看记录失败: $e", st);
    }
  }

  /// 关注用户
  Future<void> followUser() async {
    if (detail.value == null) {
      SmartDialog.showToast("直播间信息未加载完成，请稍后再试");
      return;
    }
    try {
      var id = "${site.id}_$roomId";
      var user = FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      );
      await DBService.instance.addFollow(user);
      followed.value = true;
      EventBus.instance.emit(Constant.kUpdateFollow, id);
      SmartDialog.showToast("已关注");
      Log.d("Follow saved: $id");
    } catch (e, st) {
      Log.logPrint(e);
      Log.e("关注失败: $e", st);
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      SmartDialog.showToast("关注失败，请重试");
    }
  }

  /// 取消关注用户
  Future<void> removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    try {
      var id = "${site.id}_$roomId";
      await DBService.instance.deleteFollow(id);
      followed.value = false;
      EventBus.instance.emit(Constant.kUpdateFollow, id);
      SmartDialog.showToast("已取消关注");
    } catch (e, st) {
      Log.logPrint(e);
      Log.e("取消关注失败: $e", st);
      SmartDialog.showToast("取消关注失败，请重试");
    }
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(uri: Uri.parse(detail.value!.url)));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    final request = _playback.current;
    final requestSite = site;
    final requestDetail = detail.value;
    if (!_playback.owns(request) ||
        !liveStatus.value ||
        requestDetail == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }
    final quality = qualites[currentQuality];
    try {
      final result = await requestSite.liveSite
          .getPlayUrls(detail: requestDetail, quality: quality);
      if (!_playback.owns(request)) return;
      if (result.urls.isEmpty) {
        showRoomToast("无法读取播放地址");
        return;
      }
      Utils.copyToClipboard(result.urls.first);
      showRoomToast("已复制播放直链");
    } catch (e, st) {
      if (!_playback.owns(request)) return;
      Log.e("复制播放地址失败: $e", st);
      showRoomToast("无法读取播放地址");
    }
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  double _savedVolumeBeforeMute = 50.0;

  void toggleMute() {
    final currentVolume = playbackVolume.value;
    if (currentVolume > 0) {
      _savedVolumeBeforeMute = currentVolume;
      setRoomVolume(0);
    } else {
      final v = _savedVolumeBeforeMute > 0 ? _savedVolumeBeforeMute : 50.0;
      setRoomVolume(v);
    }
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) {
          Get.back();
          currentQuality = e ?? 0;
          getPlayUrl();
        },
        child: ListView.builder(
          itemCount: qualites.length,
          itemBuilder: (_, i) {
            var item = qualites[i];
            return RadioListTile(value: i, title: Text(item.quality));
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          //currentLineIndex = i;
          //setPlayer();
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(playUrls[i].contains(".flv") ? "FLV" : "HLS"),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: (e) {
            AppSettingsController.instance.setScaleMode(e ?? 0);
            updateScaleMode();
          },
          child: ListView(
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance.addShieldList(
        keywordController.text.trim(),
      );
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(item, style: Get.textTheme.bodyMedium),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    Utils.showBottomSheet(
      title: "关注列表",
      child: Obx(
        () => Stack(
          children: [
            RefreshIndicator(
              onRefresh: FollowService.instance.loadData,
              child: ListView.builder(
                itemCount: FollowService.instance.liveList.length,
                itemBuilder: (_, i) {
                  var item = FollowService.instance.liveList[i];
                  return Obx(
                    () => FollowUserItem(
                      item: item,
                      playing: rxSite.value.id == item.siteId &&
                          rxRoomId.value == item.roomId,
                      onTap: () {
                        Get.back();
                        resetRoom(Sites.allSites[item.siteId]!, item.roomId);
                      },
                    ),
                  );
                },
              ),
            ),
            if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
              Positioned(
                right: 12,
                bottom: 12,
                child: Obx(
                  () => DesktopRefreshButton(
                    refreshing: FollowService.instance.updating.value,
                    onPressed: FollowService.instance.loadData,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text("启用定时关闭", style: Get.textTheme.titleMedium),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration = Duration(
                  hours: value.hour,
                  minutes: value.minute,
                );
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance.setRoomAutoExitDuration(
                  autoExitMinutes.value,
                );
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) return;
    final generation = _playback.beginRoom();
    if (!_playback.ownsRoom(generation)) return;
    _openedAt = DateTime.now();
    rxSite.value = site;
    rxRoomId.value = roomId;
    liveDanmaku.stop();
    _liveDurationTimer?.cancel();
    liveDuration.value = "00:00:00";
    messages.clear();
    superChats.clear();
    danmakuController?.clear();
    _playerHasCurrentPlaylist = false;
    detail.value = null;
    qualites.clear();
    playUrls.clear();
    liveStatus.value = false;
    currentQuality = currentLineIndex = -1;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    liveDanmaku = site.liveSite.getDanmaku();
    // A newer refresh/reset may supersede us while native stop is pending.
    try {
      await _playback.command(_playback.current, player.stop);
      if (_playback.ownsRoom(generation)) await loadData();
    } catch (e, st) {
      if (_playback.ownsRoom(generation)) {
        Log.e("切换直播间失败: $e", st);
        loadError.value = true;
      }
    }
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${error?.stackTrace}''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;
    }
  }

  // 用于启动开播时长计算和更新的函数
  void startLiveDurationTimer() {
    // 如果不是直播状态或者 showTime 为空，则不启动定时器
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 取消之前的定时器
      _liveDurationTimer?.cancel();
      // 创建新的定时器，每秒更新一次
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 错误时显示 --:--:--
    }
  }

  @override
  Future<void> silenceForDesktopClose() {
    _playback.suspend();
    ++_autoExitGeneration;
    autoExitTimer?.cancel();
    _autoExitGraceTimer?.cancel();
    liveDanmaku.stop();
    return super.silenceForDesktopClose();
  }

  @override
  Future<void> restoreAfterDesktopClose() {
    if (!_roomClosing) {
      _playback.resume();
      _autoExiting = false;
      refreshRoom();
      if (autoExitEnable.value && countdown.value > 0) {
        setAutoExit(resetCountdown: false);
      }
    }
    return super.restoreAfterDesktopClose();
  }

  @override
  Future<void> beforePlayerDispose() => _playback.drained;

  bool _roomClosing = false;

  @override
  void preparePlayerClose() {
    if (_roomClosing) return;
    _roomClosing = true;
    _playback.close();
    ++_autoExitGeneration;
    _autoExitGraceTimer?.cancel();
    hideRoomLoading();
    _followSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();

    liveDanmaku.stop();
    scrollController.dispose();
    _liveDurationTimer?.cancel(); // 页面关闭时取消定时器
  }

  @override
  void onClose() {
    preparePlayerClose();
    super.onClose();
  }
}

class _RoomRequest {
  final int generation;
  final Site site;
  String roomId;
  final LiveDanmaku danmaku;
  _RoomRequest(this.generation, this.site, this.roomId, this.danmaku);
}
